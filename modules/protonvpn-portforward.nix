# ProtonVPN NAT-PMP port forwarding — requests a public port from the VPN
# gateway via libnatpmp, opens it in the NixOS firewall, and pushes it to
# the running qBittorrent GUI via the WebUI API so peers can connect in.
#
# Without this, qBittorrent is connect-out-only behind Proton's NAT —
# the classic 50-80% swarm-throughput haircut and effectively no seeding.
#
# Lifecycle: BindsTo wg-quick-protonvpn → dies with the tunnel.
# Restart=always → re-establishes after protonvpn-reconnect restarts wg-quick.
# NAT-PMP only works on P2P-flagged Proton servers — set refreshPool.p2p = true.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.protonvpn.portForward;
in
{
  options.modules.protonvpn.portForward = {
    enable = lib.mkEnableOption "NAT-PMP port forwarding for qBittorrent via ProtonVPN";

    gateway = lib.mkOption {
      type = lib.types.str;
      default = "10.2.0.1";
      description = "ProtonVPN tunnel gateway (NAT-PMP target). Matches protonvpn.nix tunnel DNS.";
    };

    webuiPort = lib.mkOption {
      type = lib.types.int;
      default = 8080;
      description = "qBittorrent WebUI port (must match the seeded WebUI\\Port).";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "protonvpn";
      description = "WireGuard tunnel interface name.";
    };

    lifetime = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "NAT-PMP mapping lifetime in seconds.";
    };

    renewInterval = lib.mkOption {
      type = lib.types.int;
      default = 45;
      description = "Renewal interval in seconds (must be < lifetime).";
    };
  };

  config = lib.mkIf (config.modules.protonvpn.enable && cfg.enable) {
    # Open all high ports on the VPN interface for incoming peer connections.
    # The VPN's server-side NAT already limits reachable ports to only the
    # NAT-PMP-forwarded one — this just prevents the NixOS firewall from
    # dropping the forwarded traffic. Dynamic nftables management is
    # unnecessary because the NAT is the real access control.
    networking.firewall.interfaces.${cfg.interface} = {
      allowedTCPPortRanges = [
        {
          from = 1024;
          to = 65535;
        }
      ];
      allowedUDPPortRanges = [
        {
          from = 1024;
          to = 65535;
        }
      ];
    };

    systemd.services.protonvpn-portforward = {
      description = "ProtonVPN NAT-PMP port forwarding for qBittorrent";
      bindsTo = [ "wg-quick-protonvpn.service" ];
      after = [ "wg-quick-protonvpn.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.libnatpmp
        pkgs.curl
        pkgs.gawk
        pkgs.coreutils
      ];
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        ExecStart = pkgs.writeShellScript "protonvpn-portforward" ''
          set -euo pipefail
          GATEWAY="${cfg.gateway}"
          LIFETIME=${toString cfg.lifetime}
          RENEW=${toString cfg.renewInterval}
          WEBUI_PORT=${toString cfg.webuiPort}
          PORT_PREV=""

          while :; do
            # Request UDP mapping (private port 1 = placeholder; Proton assigns
            # the same port on both sides regardless of what we request).
            UDP_OUT=$(natpmpc -g "$GATEWAY" -a 1 0 udp "$LIFETIME" 2>&1) || {
              echo "natpmpc UDP failed (server not P2P / no NAT-PMP?): $UDP_OUT"
              sleep 5; continue
            }
            PORT=$(printf '%s\n' "$UDP_OUT" | awk '/^Mapped public port/ {print $4; exit}')
            [ -n "$PORT" ] || { echo "no port parsed from natpmpc output"; sleep 5; continue; }

            # Map TCP to the same public port (BitTorrent uses both).
            natpmpc -g "$GATEWAY" -a 1 "$PORT" tcp "$LIFETIME" >/dev/null 2>&1 || \
              natpmpc -g "$GATEWAY" -a 1 0 tcp "$LIFETIME" >/dev/null 2>&1 || true

            if [ "$PORT" != "$PORT_PREV" ]; then
              echo "NAT-PMP port changed: ''${PORT_PREV:-none} -> $PORT"
              PORT_PREV="$PORT"
            fi

            # Push the port to the running qBittorrent GUI (localhost, no auth).
            curl -fsS --max-time 5 --data "json={\"listen_port\":$PORT}" \
              "http://127.0.0.1:$WEBUI_PORT/api/v2/app/setPreferences" 2>/dev/null \
              || echo "qBittorrent WebUI push failed (app not running?) — mapping kept alive"

            sleep "$RENEW"
          done
        '';
      };
    };
  };
}
