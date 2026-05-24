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
      };
      modules = [
        ../hosts/${hostName}
        ../overlays
        ../modules/base.nix
        ../modules/nix.nix
        ../modules/nix-ld.nix
        ../modules/kernel.nix
        ../modules/hardware.nix
        ../modules/system.nix
        ../modules/networking.nix
        ../modules/desktop.nix
        ../modules/audio.nix
        ../modules/fonts.nix
        ../modules/gaming.nix
        ../modules/apps.nix
        ../modules/ollama.nix
        ../modules/hardening.nix
        ../modules/hyprland.nix
        ../modules/theming.nix
        ../modules/containers.nix
        # wazuh-manager.nix unconditionally declares the
        # virtualisation.oci-containers stack (no enable gate). Without the
        # one-time manual cert bootstrap (see the module header), all three
        # containers restart-loop forever — burning CPU/disk and flooding
        # the journal (observed on the box). Disabled until the certs exist;
        # re-add this import after completing the cert setup. Mirrors the
        # disabled-by-default posture of wazuh-agent.nix.
        # ../modules/wazuh-manager.nix
        ../modules/wazuh-agent.nix
        ../modules/protonvpn.nix
        ../modules/protonvpn-rotate.nix
        ../modules/media-server.nix
        ../modules/auditd.nix
        ../modules/fan-control.nix
        ../modules/update-routines.nix
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
