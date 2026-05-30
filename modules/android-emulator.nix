# Android emulator isolation module — QEMU/KVM VM on a dedicated bridge with VPN-only egress.
# Gated behind modules.androidEmulator.enable (default false).
{
  config,
  lib,
  pkgs,
  host,
  ...
}:

# Runs an Android-x86 (or similar) VM via libvirt/QEMU with a dedicated
# WireGuard tunnel (protonvpn-android) and an nftables kill switch that
# restricts the VM bridge (virbr-android) to egress only through that tunnel.
#
# Key design decisions:
#   - Separate WireGuard interface (protonvpn-android) from the main protonvpn
#     tunnel — the VM traffic gets its own VPN identity and does not share
#     the host's tunnel.
#   - autostart = false: the VPN tunnel is brought up on demand (by the
#     android-emu-start helper script) rather than at boot.
#   - table = "off": wg-quick does not install a default route — IP forwarding
#     + nftables MASQUERADE handle routing of VM bridge traffic explicitly.
#   - The kill switch is a systemd oneshot service (same pattern as
#     protonvpn.nix) that loads an nftables table; it starts before libvirtd
#     so the rule is in place before the bridge can carry traffic.

let
  cfg = config.modules.androidEmulator;

  # VM bridge interface name (libvirt network "android" will create this).
  bridgeIface = "virbr-android";

  # WireGuard tunnel interface for the Android VM.
  vpnIface = "protonvpn-android";
in
{
  options.modules.androidEmulator = {
    enable = lib.mkEnableOption "Android emulator VM with isolated VPN egress";

    vpn = {
      serverPublicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          WireGuard [Peer] PublicKey for the ProtonVPN server the Android VM
          will use. Obtain from account.proton.me → WireGuard configurations.
        '';
      };

      serverEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "146.70.146.34:51820";
        description = ''
          WireGuard [Peer] Endpoint (IP:port) for the ProtonVPN server.
        '';
      };

      clientAddress = lib.mkOption {
        type = lib.types.str;
        default = "10.2.0.2/32";
        description = ''
          WireGuard [Interface] Address assigned to this tunnel by ProtonVPN.
        '';
      };

      privateKeyFile = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/android-emulator/vpn-privkey";
        description = ''
          Path to the WireGuard private key file for the Android VM tunnel.
          Place the key here or point to a sops-nix secret path.
        '';
      };
    };

    vm = {
      cpus = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4;
        description = "Number of virtual CPUs to assign to the Android VM.";
      };

      memoryMB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4096;
        description = "RAM in MiB to assign to the Android VM.";
      };

      diskGB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 32;
        description = "Disk image size in GiB for the Android VM.";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.vpn.serverPublicKey != "";
        message = "modules.androidEmulator.vpn.serverPublicKey must be set when enabled.";
      }
      {
        assertion = cfg.vpn.serverEndpoint != "";
        message = "modules.androidEmulator.vpn.serverEndpoint must be set (format IP:port).";
      }
    ];

    # ── libvirt / QEMU ──────────────────────────────────────────────────────
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = false;
        ovmf.enable = true; # UEFI firmware for the VM
      };
    };

    programs.virt-manager.enable = true;

    users.users.${host.user}.extraGroups = [
      "libvirtd"
      "kvm"
    ];

    # ── helper scripts ───────────────────────────────────────────────────────
    environment.systemPackages = [
      (pkgs.callPackage ../packages/android-emu-start.nix { inherit host; })
      (pkgs.callPackage ../packages/android-emu-gps.nix { inherit host; })
    ];

    # ── emulator working directory ───────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${host.home}/android-emulator 0750 ${host.user} users -"
    ];

    # ── dedicated WireGuard tunnel for the Android VM ────────────────────────
    # autostart = false — brought up on demand by android-emu-start.
    # table = "off"    — wg-quick does not touch the routing table; nftables
    #                    MASQUERADE + forwarding rules handle VM egress.
    networking.wg-quick.interfaces.${vpnIface} = {
      address = [ cfg.vpn.clientAddress ];
      dns = [ "10.2.0.1" ];
      privateKeyFile = toString cfg.vpn.privateKeyFile;
      autostart = false;
      mtu = 1420;
      table = "off";
      peers = [
        {
          publicKey = cfg.vpn.serverPublicKey;
          allowedIPs = [ "0.0.0.0/0" ];
          endpoint = cfg.vpn.serverEndpoint;
          persistentKeepalive = 25;
        }
      ];
    };

    # ── IP forwarding (required for bridge → VPN routing) ───────────────────
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
    };

    # ── nftables kill switch for the VM bridge ───────────────────────────────
    # Allows forwarded traffic from virbr-android only when it exits through
    # protonvpn-android. All other forwarded paths from the bridge are dropped.
    # The table is named android_killswitch to keep it isolated from the main
    # protonvpn_killswitch table (both can coexist).
    systemd.services.android-emu-killswitch = {
      description = "Android emulator kill switch (VM bridge → VPN only)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-pre.target" ];
      before = [ "libvirtd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "android-emu-killswitch-up" ''
          set -e
          ${pkgs.nftables}/bin/nft -f - <<'NFTEOF'
          table inet android_killswitch {}
          flush table inet android_killswitch
          table inet android_killswitch {
            chain forward {
              type filter hook forward priority 0; policy accept;
              # Drop bridged VM traffic that is NOT leaving via the VPN tunnel.
              iifname "${bridgeIface}" oifname != "${vpnIface}" drop
            }
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              # MASQUERADE VM traffic leaving through the VPN tunnel so the
              # ProtonVPN peer sees the tunnel address, not the bridge subnet.
              iifname "${bridgeIface}" oifname "${vpnIface}" masquerade
            }
          }
          NFTEOF
        '';
        ExecStop = pkgs.writeShellScript "android-emu-killswitch-down" ''
          ${pkgs.nftables}/bin/nft delete table inet android_killswitch 2>/dev/null || true
        '';
      };
    };
  };
}
