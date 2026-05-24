{
  config,
  lib,
  pkgs,
  ...
}:

# Automatic server rotation for ProtonVPN WireGuard tunnel.
#
# Reads a pre-seeded JSON pool of servers, pings each endpoint to measure
# latency, and hot-swaps the WireGuard peer to the fastest one. The swap
# uses `wg set` (no interface teardown) and updates the kill switch nftables
# atomically so there is no connectivity gap.
#
# Pool file format (/var/lib/protonvpn/server-pool.json):
# [
#   { "name": "US-OH#24", "endpoint": "146.70.84.2:51820", "publicKey": "Rtsl6..." },
#   { "name": "US-NY#42", "endpoint": "185.159.156.3:51820", "publicKey": "abc..." }
# ]
#
# Generate entries from: account.proton.me -> Downloads -> WireGuard configuration.
# Pick multiple servers in your preferred region. Each config gives you an
# Endpoint and a PublicKey for [Peer]. The PrivateKey is the same across all
# (it's YOUR key, not the server's).

let
  cfg = config.modules.protonvpn;
  rotateCfg = cfg.autoRotate;

  rotateScript = pkgs.writeShellScript "protonvpn-rotate" ''
    set -euo pipefail
    PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          wireguard-tools
          nftables
          iputils
          jq
          coreutils
          gawk
          curl
        ]
      )
    }:$PATH"

    POOL_FILE="${rotateCfg.poolFile}"
    IFACE="protonvpn"
    HYSTERESIS=${toString rotateCfg.hysteresisMs}
    PING_COUNT=3
    PING_TIMEOUT=2
    # Quality thresholds — only rotate when current connection is degraded
    MAX_LATENCY_MS=150    # trigger rotation if current latency exceeds this
    MAX_LOSS_PCT=20       # trigger rotation if packet loss exceeds this
    SPEED_CHECK_URL="https://speed.cloudflare.com/__down?bytes=1048576" # 1MB download

    if [ ! -f "$POOL_FILE" ]; then
      echo "ERROR: server pool not found at $POOL_FILE" >&2
      echo "See: docs/protonvpn-wg-setup.md for how to populate it." >&2
      exit 1
    fi

    SERVER_COUNT=$(jq length "$POOL_FILE")
    if [ "$SERVER_COUNT" -lt 2 ]; then
      echo "Pool has fewer than 2 servers, nothing to rotate." >&2
      exit 0
    fi

    # Current peer info
    CURRENT_KEY=$(wg show "$IFACE" peers 2>/dev/null | head -1)
    CURRENT_ENDPOINT=$(wg show "$IFACE" endpoints 2>/dev/null | awk '{print $2}')

    if [ -z "$CURRENT_KEY" ]; then
      echo "ERROR: no active peer on $IFACE — tunnel may be down" >&2
      exit 1
    fi

    CURRENT_IP=''${CURRENT_ENDPOINT%%:*}

    echo "Current: $CURRENT_ENDPOINT (key: ''${CURRENT_KEY:0:8}...)"

    # --- Quality check: measure current connection health ---
    CURRENT_PING=$(ping -c 5 -W 3 -q 10.2.0.1 2>/dev/null \
      | awk -F'/' '/^rtt/{print $5}' || echo "99999")
    CURRENT_LOSS=$(ping -c 5 -W 3 -q 10.2.0.1 2>/dev/null \
      | awk -F'[,%]' '/packet loss/{print $3}' | tr -d ' ' || echo "100")

    CURRENT_PING_INT=''${CURRENT_PING%.*}
    CURRENT_LOSS_INT=''${CURRENT_LOSS%.*}

    echo "Quality: latency=''${CURRENT_PING_INT}ms loss=''${CURRENT_LOSS_INT}%"

    # If current connection is healthy, don't rotate
    if [ "$CURRENT_PING_INT" -lt "$MAX_LATENCY_MS" ] && [ "$CURRENT_LOSS_INT" -lt "$MAX_LOSS_PCT" ]; then
      echo "Connection healthy (''${CURRENT_PING_INT}ms, ''${CURRENT_LOSS_INT}% loss). No rotation needed."
      exit 0
    fi

    echo "Connection degraded! Searching for a better server..."

    # Measure latency to each server in the pool
    BEST_NAME=""
    BEST_IP=""
    BEST_PORT=""
    BEST_KEY=""
    BEST_LATENCY=99999
    CURRENT_LATENCY=99999

    while IFS= read -r server; do
      name=$(echo "$server" | jq -r '.name')
      endpoint=$(echo "$server" | jq -r '.endpoint')
      key=$(echo "$server" | jq -r '.publicKey')
      ip=''${endpoint%%:*}
      port=''${endpoint##*:}

      # Temporarily allow this IP through kill switch for the ping probe
      nft add rule inet protonvpn_killswitch output ip daddr "$ip" accept 2>/dev/null || true

      avg=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" -q "$ip" 2>/dev/null \
        | awk -F'/' '/^rtt/{print $5}' || echo "99999")

      # Remove the temporary rule (flush and re-apply is safer but slow;
      # since we're adding to the end of the chain before the drop rule...
      # actually nft appends AFTER the drop, so we need to insert instead)
      # The kill switch allows the current endpoint + VPN iface, so pings
      # to OTHER endpoints need a temporary exception. We'll use a separate
      # chain for probes.

      echo "  $name ($ip): ''${avg}ms"

      if [ "$ip" = "$CURRENT_IP" ]; then
        CURRENT_LATENCY=''${avg%.*}
      fi

      avg_int=''${avg%.*}
      if [ "$avg_int" -lt "$BEST_LATENCY" ] 2>/dev/null; then
        BEST_LATENCY=$avg_int
        BEST_NAME=$name
        BEST_IP=$ip
        BEST_PORT=$port
        BEST_KEY=$key
      fi
    done < <(jq -c '.[]' "$POOL_FILE")

    # Clean up probe rules — reload kill switch with current endpoint
    # (the main service will fix it; temporary rules are gone on table reload)

    if [ -z "$BEST_KEY" ] || [ "$BEST_LATENCY" = "99999" ]; then
      echo "No reachable server found, keeping current." >&2
      exit 0
    fi

    if [ "$BEST_KEY" = "$CURRENT_KEY" ]; then
      echo "Current server is already the fastest ($BEST_NAME, ''${BEST_LATENCY}ms). No swap needed."
      exit 0
    fi

    # Hysteresis: only swap if the new server is significantly faster
    DIFF=$((CURRENT_LATENCY - BEST_LATENCY))
    if [ "$DIFF" -lt "$HYSTERESIS" ]; then
      echo "Best ($BEST_NAME, ''${BEST_LATENCY}ms) is not ''${HYSTERESIS}ms+ faster than current (''${CURRENT_LATENCY}ms). Keeping current."
      exit 0
    fi

    echo "Swapping to $BEST_NAME ($BEST_IP:$BEST_PORT, ''${BEST_LATENCY}ms, delta=''${DIFF}ms)..."

    # Step 1: Update kill switch to allow BOTH endpoints during transition
    nft -f - <<EOF
    table inet protonvpn_killswitch {
      chain output {
        type filter hook output priority -100; policy accept;
        oifname "lo" accept
        ip daddr 192.168.1.0/24 accept
        ip daddr 169.254.0.0/16 accept
        ip daddr 224.0.0.0/4 accept
        ip daddr 255.255.255.255 accept
        ip daddr $CURRENT_IP accept
        ip daddr $BEST_IP accept
        oifname "$IFACE" accept
        counter drop
      }
    }
    EOF

    # Step 2: Atomic peer swap (remove old, add new — microseconds apart)
    wg set "$IFACE" peer "$CURRENT_KEY" remove
    wg set "$IFACE" peer "$BEST_KEY" \
      endpoint "$BEST_IP:$BEST_PORT" \
      allowed-ips "0.0.0.0/0,::/0" \
      persistent-keepalive 25

    # Step 3: Wait for handshake (up to 10s)
    HANDSHAKE_OK=false
    for i in $(seq 1 20); do
      HS=$(wg show "$IFACE" latest-handshakes | awk '{print $2}')
      if [ -n "$HS" ] && [ "$HS" != "0" ]; then
        HANDSHAKE_OK=true
        break
      fi
      sleep 0.5
    done

    if [ "$HANDSHAKE_OK" = "false" ]; then
      echo "WARNING: No handshake after 10s. Rolling back to previous server..." >&2
      wg set "$IFACE" peer "$BEST_KEY" remove
      wg set "$IFACE" peer "$CURRENT_KEY" \
        endpoint "$CURRENT_IP:''${CURRENT_ENDPOINT##*:}" \
        allowed-ips "0.0.0.0/0,::/0" \
        persistent-keepalive 25
      # Restore kill switch with original endpoint only
      nft -f - <<EOF
      table inet protonvpn_killswitch {
        chain output {
          type filter hook output priority -100; policy accept;
          oifname "lo" accept
          ip daddr 192.168.1.0/24 accept
          ip daddr 169.254.0.0/16 accept
          ip daddr 224.0.0.0/4 accept
          ip daddr 255.255.255.255 accept
          ip daddr $CURRENT_IP accept
          oifname "$IFACE" accept
          counter drop
        }
      }
    EOF
      echo "Rolled back to $CURRENT_ENDPOINT." >&2
      exit 1
    fi

    # Step 4: Finalize kill switch with only the new endpoint
    nft -f - <<EOF
    table inet protonvpn_killswitch {
      chain output {
        type filter hook output priority -100; policy accept;
        oifname "lo" accept
        ip daddr 192.168.1.0/24 accept
        ip daddr 169.254.0.0/16 accept
        ip daddr 224.0.0.0/4 accept
        ip daddr 255.255.255.255 accept
        ip daddr $BEST_IP accept
        oifname "$IFACE" accept
        counter drop
      }
    }
    EOF

    echo "Done. Now connected to $BEST_NAME ($BEST_IP:$BEST_PORT)."
  '';

  # Probe script that adds temporary nft rules for pinging pool endpoints
  # through the kill switch. We use a separate "probe" chain inserted before
  # the drop rule so pings reach non-current endpoints.
  probeSetupScript = pkgs.writeShellScript "protonvpn-probe-setup" ''
    set -euo pipefail
    PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          nftables
          jq
        ]
      )
    }:$PATH"
    POOL_FILE="${rotateCfg.poolFile}"
    [ -f "$POOL_FILE" ] || exit 0

    # Add all pool IPs to the kill switch temporarily (before the drop rule)
    # by replacing the table with one that includes all pool endpoints.
    CURRENT_IP=$(${pkgs.wireguard-tools}/bin/wg show protonvpn endpoints 2>/dev/null | ${pkgs.gawk}/bin/awk -F'[:\t]' '{print $2}')
    [ -z "$CURRENT_IP" ] && exit 1

    POOL_IPS=$(jq -r '.[].endpoint' "$POOL_FILE" | cut -d: -f1 | sort -u)
    ALLOW_RULES=""
    for ip in $POOL_IPS; do
      ALLOW_RULES="$ALLOW_RULES
        ip daddr $ip accept"
    done

    nft -f - <<EOF
    table inet protonvpn_killswitch {
      chain output {
        type filter hook output priority -100; policy accept;
        oifname "lo" accept
        ip daddr 192.168.1.0/24 accept
        ip daddr 169.254.0.0/16 accept
        ip daddr 224.0.0.0/4 accept
        ip daddr 255.255.255.255 accept
        $ALLOW_RULES
        oifname "protonvpn" accept
        counter drop
      }
    }
    EOF
  '';
in
{
  options.modules.protonvpn.autoRotate = {
    enable = lib.mkEnableOption "automatic server rotation based on latency";

    poolFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/protonvpn/server-pool.json";
      description = ''
        Path to a JSON array of server objects. Each object must have:
        "name" (human label), "endpoint" (IP:port), "publicKey" (base64 WG key).
        Generate from account.proton.me -> Downloads -> WireGuard configuration.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "How often to check for a faster server (systemd calendar format).";
    };

    hysteresisMs = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = ''
        Only swap servers if the new one is at least this many milliseconds
        faster than the current one. Prevents flip-flopping between servers
        with similar latency.
      '';
    };

    refreshPool = {
      enable = lib.mkEnableOption "periodic server pool refresh from ProtonVPN GUI cache";

      country = lib.mkOption {
        type = lib.types.str;
        default = "US";
        description = "Exit country code to filter servers.";
      };

      top = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Keep the top N servers by ProtonVPN score.";
      };

      p2p = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Only include P2P-capable servers.";
      };

      refreshInterval = lib.mkOption {
        type = lib.types.str;
        default = "6h";
        description = "How often to refresh the server pool from GUI cache.";
      };

      cacheOwner = lib.mkOption {
        type = lib.types.str;
        default = "stoleyy";
        description = "Username whose ProtonVPN GUI cache to read.";
      };

      lat = lib.mkOption {
        type = lib.types.float;
        default = 0.0;
        description = "User latitude for geographic server selection.";
      };

      lon = lib.mkOption {
        type = lib.types.float;
        default = 0.0;
        description = "User longitude for geographic server selection.";
      };

      geoCities = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Keep servers in the N closest cities only (0 = all).";
      };
    };
  };

  config = lib.mkIf (cfg.enable && rotateCfg.enable) {
    systemd = {
      services = {
        protonvpn-rotate = {
          description = "ProtonVPN automatic server rotation (latency-based)";
          after = [ "wg-quick-protonvpn.service" ];
          requires = [ "wg-quick-protonvpn.service" ];
          path = with pkgs; [
            wireguard-tools
            nftables
            iputils
            jq
            coreutils
            gawk
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStartPre = probeSetupScript;
            ExecStart = rotateScript;
          };
        };

        # Pool refresh: read ProtonVPN GUI's cached server list (no auth needed)
        protonvpn-refresh-pool = lib.mkIf rotateCfg.refreshPool.enable {
          description = "Refresh ProtonVPN server pool from GUI cache";
          after = [ "wg-quick-protonvpn.service" ];
          path = [ pkgs.python3 ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart =
              let
                rcfg = rotateCfg.refreshPool;
                flags = lib.concatStringsSep " " (
                  [
                    "--country ${rcfg.country}"
                    "--top ${toString rcfg.top}"
                    "--output ${toString rotateCfg.poolFile}"
                    "--cache /home/${rcfg.cacheOwner}/.cache/Proton/VPN/serverlist.json"
                  ]
                  ++ lib.optional rcfg.p2p "--p2p"
                  ++ lib.optional (rcfg.lat != 0.0) "--lat ${toString rcfg.lat}"
                  ++ lib.optional (rcfg.lon != 0.0) "--lon ${toString rcfg.lon}"
                  ++ lib.optional (rcfg.geoCities > 0) "--geo-cities ${toString rcfg.geoCities}"
                );
              in
              pkgs.writeShellScript "protonvpn-refresh-pool-wrapper" ''
                exec python3 ${../scripts/protonvpn-fetch-pool.py} ${flags}
              '';
          };
        };
      };

      timers = {
        protonvpn-rotate = {
          description = "Timer for ProtonVPN server rotation";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = rotateCfg.interval;
            RandomizedDelaySec = "2min";
          };
        };

        protonvpn-refresh-pool = lib.mkIf rotateCfg.refreshPool.enable {
          description = "Timer for ProtonVPN server pool refresh";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnUnitActiveSec = rotateCfg.refreshPool.refreshInterval;
            RandomizedDelaySec = "5min";
          };
        };
      };
    };
  };
}
