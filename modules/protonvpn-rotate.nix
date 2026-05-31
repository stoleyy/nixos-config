# ProtonVPN server rotation — quality-based health checks, automatic wg-quick peer swap.
{
  config,
  lib,
  pkgs,
  ...
}:

# Automatic server rotation for ProtonVPN WireGuard tunnel.
#
# Quality-based: checks current connection health every interval, only
# rotates when latency or packet loss exceeds thresholds. The swap is
# atomic (wg set peer remove/add) with nftables kill switch updates.
#
# Pool file format (/var/lib/protonvpn/server-pool.json):
# [
#   { "name": "US-OH#24", "endpoint": "146.70.84.2:51820", "publicKey": "Rtsl6..." },
#   { "name": "US-NY#42", "endpoint": "185.159.156.3:51820", "publicKey": "abc..." }
# ]

let
  cfg = config.modules.protonvpn;
  rotateCfg = cfg.autoRotate;

  inherit (import ../lib/nftables.nix { inherit lib; }) mkKillswitchTable;

  binPath = lib.makeBinPath (
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
  );

  # Pre-render nftables tables at eval time. The shell variables
  # ($CURRENT_IP, $BEST_IP) are literal strings in Nix — they appear
  # verbatim in the generated script and expand at runtime via the
  # unquoted heredoc.
  rotateScript = pkgs.runCommandLocal "protonvpn-rotate.sh" { } ''
    cp ${
      pkgs.replaceVars ../scripts/protonvpn-rotate.sh {
        inherit (pkgs) bash;
        path = binPath;
        poolFile = toString rotateCfg.poolFile;
        hysteresis = toString rotateCfg.hysteresisMs;
        killswitchBoth = mkKillswitchTable [
          "$CURRENT_IP"
          "$BEST_IP"
        ];
        killswitchCurrent = mkKillswitchTable [ "$CURRENT_IP" ];
        killswitchBest = mkKillswitchTable [ "$BEST_IP" ];
      }
    } $out
    chmod +x $out
  '';

  probeScript = pkgs.runCommandLocal "protonvpn-probe.sh" { } ''
    cp ${
      pkgs.replaceVars ../scripts/protonvpn-probe.sh {
        inherit (pkgs) bash;
        path = lib.makeBinPath (
          with pkgs;
          [
            nftables
            jq
            wireguard-tools
            gawk
          ]
        );
        poolFile = toString rotateCfg.poolFile;
      }
    } $out
    chmod +x $out
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
      description = "How often to check connection quality (systemd calendar format).";
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
        description = "Keep the top N servers by ProtonVPN score (0 = all).";
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
          description = "ProtonVPN quality-based server rotation";
          after = [ "wg-quick-protonvpn.service" ];
          requires = [ "wg-quick-protonvpn.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStartPre = "${probeScript}";
            ExecStart = "${rotateScript}";
          };
        };

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
          description = "Timer for ProtonVPN quality-based rotation";
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
