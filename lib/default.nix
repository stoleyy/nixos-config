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
        ../modules/networking.nix # NetworkManager, nftables, resolved

        # ── Desktop & UX ──
        ../modules/desktop.nix # SDDM, Plasma 6, XDG portals
        ../modules/hyprland.nix # Hyprland session (default, autologin)
        ../modules/audio.nix # PipeWire, low-latency, BT codecs
        ../modules/fonts.nix # Noto, Liberation, JetBrainsMono
        ../modules/theming.nix # Papirus icons, cava

        # ── Applications ──
        ../modules/apps.nix # Brave, Zen, CLI tools, ProtonVPN GUI
        ../modules/gaming.nix # Steam, GameMode, gamescope, game-install
        ../modules/ollama.nix # local LLM inference (CUDA)

        # ── Security & monitoring ──
        ../modules/hardening.nix # CIS/KSPP sysctl, AppArmor
        ../modules/auditd.nix # syscall/FIM audit → Wazuh
        ../modules/wazuh-agent.nix # HIDS agent
        # ../modules/wazuh-manager.nix # disabled — pending cert bootstrap

        # ── Networking services ──
        ../modules/protonvpn.nix # WireGuard tunnel + kill switch
        ../modules/protonvpn-rotate.nix # quality-based server rotation
        ../modules/containers.nix # Podman/OCI runtime
        ../modules/media-server.nix # Jellyfin, *arr stack, qBittorrent
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
              theme = import ../lib/theme.nix;
            };
            sharedModules = [
              inputs.plasma-manager.homeModules.plasma-manager
              inputs.nix-index-database.homeModules.nix-index
            ];
            users.stoleyy = import ../home/stoleyy;
          };
        }
      ]
      ++ extraModules;
    };
}
