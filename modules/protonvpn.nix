{
  config,
  lib,
  pkgs,
  ...
}:

# ProtonVPN via kernel WireGuard (wg-quick), boot-time activation.
#
# Why not the ProtonVPN GUI client (modules/apps.nix still installs it):
#   - The GUI requires a logged-in session and a running tray app to keep the
#     tunnel up. Kernel wg-quick comes up at boot via systemd, before SDDM
#     even starts.
#   - Kill switch is enforced at the firewall level here; the GUI's killswitch
#     toggle works but is process-based and has been observed to fail-open
#     during NetworkManager re-establishment.
#
# Coexistence: leave protonvpn-gui installed as a fallback for picking a
# specific server interactively. Don't run both tunnels simultaneously
# (they'd race for the default route).
#
# Setup steps live in docs/protonvpn-wg-setup.md.

let
  cfg = config.modules.protonvpn;

  # endpoint IP (without port) extracted for the kill-switch rule
  endpointHost = builtins.head (lib.splitString ":" cfg.serverEndpoint);

  inherit (import ../lib/nftables.nix { inherit lib; }) mkKillswitchTable;
in
{
  options.modules.protonvpn = {
    enable = lib.mkEnableOption "ProtonVPN via wg-quick (kernel WireGuard, boot-time)";

    serverPublicKey = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The `[Peer] PublicKey =` value from your Proton-issued WireGuard config
        (account.proton.me → Downloads → WireGuard configurations).
      '';
    };

    serverEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "146.70.146.34:51820";
      description = ''
        The `[Peer] Endpoint =` value from your Proton WireGuard config.
        Format: `IP:port`. Port is almost always 51820.
      '';
    };

    clientAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.2.0.2/32";
      description = ''
        The `[Interface] Address =` value from your Proton WireGuard config.
        Proton typically issues 10.2.0.2/32 on the tunnel.
      '';
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/protonvpn/privkey";
      description = ''
        Path to a root-owned mode-0400 file containing only the WireGuard
        private key (just the base64 string, no quotes, no header). NixOS
        won't read this file — wg-quick does at activation time. See
        docs/protonvpn-wg-setup.md for the one-liner to create it safely.

        Upgrade path: switch this to `config.sops.secrets.<name>.path` once
        sops-nix is wired up (Tier 2.1 in the optimization roadmap). At that
        point the private key lives encrypted in secrets.yaml.
      '';
    };

    killSwitch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When enabled, blocks all outbound traffic on the default interface
        UNLESS it's: (a) destined for the ProtonVPN endpoint itself (so the
        tunnel can establish/reconnect), (b) destined for LAN
        (192.168.1.0/24, so you can still reach OPNsense/printer/Wazuh
        dashboard), or (c) going through the `protonvpn` WireGuard interface
        itself.

        Rule lives in iptables-nft (the nftables compat path). The rule
        survives wg-quick going down (it's installed independent of
        interface state via NixOS firewall hooks), so a VPN crash does NOT
        leak traffic.

        Disable if you need the GUI client to coexist or want full flexibility.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Sanity: refuse to evaluate if required fields aren't set. Catches the
    # common mistake of toggling `enable = true` without populating the
    # Proton-side values.
    assertions = [
      {
        assertion = cfg.serverPublicKey != "";
        message = "modules.protonvpn.serverPublicKey must be set when enabled (see Proton WG config).";
      }
      {
        assertion = cfg.serverEndpoint != "";
        message = "modules.protonvpn.serverEndpoint must be set when enabled (format IP:port).";
      }
    ];

    networking.wg-quick.interfaces.protonvpn = {
      address = [ cfg.clientAddress ];
      # Proton's tunnel DNS — only reachable through the tunnel itself, so
      # this is leak-safe.
      dns = [ "10.2.0.1" ];
      privateKeyFile = toString cfg.privateKeyFile;
      autostart = true;
      mtu = 1420;
      peers = [
        {
          publicKey = cfg.serverPublicKey;
          allowedIPs = [
            "0.0.0.0/0"
            "::/0"
          ];
          endpoint = cfg.serverEndpoint;
          persistentKeepalive = 25;
        }
      ];
    };

    # Kill switch: install nftables rules at boot, independent of wg-quick
    # state. Even if the tunnel never comes up, non-VPN traffic is blocked.
    networking.firewall.extraInputRules = lib.mkIf cfg.killSwitch ''
      # nothing extra for input — default deny-all is already in place
    '';

    # Outbound kill switch via a dedicated systemd-managed nftables table.
    # Existing as a separate `table inet protonvpn_killswitch` keeps it
    # decoupled from NixOS's main firewall table — easier to inspect/disable.
    systemd.services.protonvpn-killswitch = lib.mkIf cfg.killSwitch {
      description = "ProtonVPN kill switch (block non-VPN outbound)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-pre.target" ];
      before = [ "wg-quick-protonvpn.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "protonvpn-killswitch-up" ''
          set -e
          ${pkgs.nftables}/bin/nft -f - <<'EOF'
          ${mkKillswitchTable [ endpointHost ]}
          EOF
        '';
        ExecStop = pkgs.writeShellScript "protonvpn-killswitch-down" ''
          ${pkgs.nftables}/bin/nft delete table inet protonvpn_killswitch 2>/dev/null || true
        '';
      };
    };
  };
}
