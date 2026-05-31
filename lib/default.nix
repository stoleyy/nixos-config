# Helper factory for declaring NixOS hosts.

{ inputs }:

{
  mkHost =
    {
      hostName,
      system ? "x86_64-linux",
      extraModules ? [ ],
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        host = import ../lib/host.nix;
      };
      modules = [
        ../hosts/${hostName}
        ../overlays

        # ── Foundation ──
        ../modules/base.nix # user account, shell, allowUnfree
        ../modules/nix.nix # daemon, caches, dev UX (nh, direnv)
        ../modules/nix-ld.nix # foreign ELF ABI shim
        ../modules/system.nix # fstrim, fwupd, journald, OOM, stateVersion

        # ── Hardware & kernel ──
        ../modules/kernel.nix # kernel pin, sysctl, THP, NVMe scheduler
        ../modules/hardware.nix # microcode, bluetooth, zram
        ../modules/fan-control.nix # it87 driver + fancontrol (Predator PO3-650)
        ../modules/nvidia.nix # NVIDIA RTX 4070 (Ada) — proprietary driver, VAAPI, undervolt
        ../modules/networking.nix # NetworkManager, nftables, resolved, anonymized DNS
        ../modules/network-privacy.nix # MAC randomization, DHCP hostname suppression, IPv6 privacy

        # ── Desktop & UX ──
        ../modules/desktop.nix # SDDM, Plasma 6, XDG portals
        ../modules/hyprland.nix # Hyprland session (default, autologin)
        ../modules/audio.nix # PipeWire, low-latency, BT codecs
        ../modules/fonts.nix # Noto, Liberation, JetBrainsMono
        ../modules/theming.nix # Papirus icons, cava

        # ── Applications ──
        ../modules/apps.nix # CLI tools, ProtonVPN GUI (browser is home/stoleyy/browser.nix)
        ../modules/gaming.nix # Steam, GameMode, gamescope, game-install
        ../modules/gamer-account.nix # low-priv gamer UID for the gaming-mode session (W1/W2)
        ../modules/android-emulator.nix # Android VM for GPS spoofing research (gated: modules.androidEmulator.enable)

        # ── Security & monitoring ──
        ../modules/compartments.nix # Qubes-style GID isolation + firejail offline vault
        ../modules/hardening.nix # CIS/KSPP sysctl, AppArmor
        ../modules/auditd.nix # syscall/FIM audit → Wazuh
        ../modules/aide.nix # offline file-integrity baseline (watches /boot, /etc, /root)
        ../modules/wazuh-agent.nix # HIDS agent
        ../modules/tor-isolation.nix # Tor SOCKS proxy for the untrusted browser domain
        ../modules/suricata.nix # network IDS on the VPN (protonvpn) egress path
        ../modules/crowdsec.nix # behavioral IPS — journald auth-abuse + local API
        # DISABLED — script runs sbctl verify against raw kernel files that lanzaboote owns; sbctl sign -s on those corrupts the lanzaboote UKI hash. Re-enable only after rewriting the script to scope to /boot/EFI/Linux/*.efi UKIs only.
        # ../modules/secureboot-verify.nix # post-activation sbctl verify gate
        # ../modules/wazuh-manager.nix # disabled — pending cert bootstrap

        # ── Networking services ──
        ../modules/protonvpn.nix # WireGuard tunnel + kill switch
        ../modules/protonvpn-rotate.nix # quality-based server rotation
        ../modules/protonvpn-portforward.nix # NAT-PMP port forwarding for qBittorrent
        ../modules/media-server.nix # Jellyfin, *arr stack, qBittorrent (gated: modules.mediaServer.enable)
        ../modules/monitoring.nix # ntfy, beszel, gatus, vector
        ../modules/transcode.nix # systemd.paths NVENC watch folder
        ../modules/update-routines.nix # weekly rebuild, flake bump, vulnix

        # ── External modules ──
        inputs.nix-gaming.nixosModules.pipewireLowLatency
        inputs.nix-gaming.nixosModules.platformOptimizations
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = {
              inherit inputs;
              host = import ../lib/host.nix;
              theme = import ../lib/theme.nix;
            };
            sharedModules = [
              inputs.plasma-manager.homeModules.plasma-manager
              inputs.nix-index-database.homeModules.nix-index
              inputs.zen-browser.homeModules.default
            ];
            users.stoleyy = import ../home/stoleyy;
          };
        }
      ]
      ++ extraModules;
    };
}
