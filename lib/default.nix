# Helper factory for declaring NixOS hosts.

{ inputs, ... }:

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
        ../modules/networking.nix
        ../modules/desktop.nix
        ../modules/audio.nix
        ../modules/fonts.nix
        ../modules/gaming.nix
        ../modules/apps.nix
        ../modules/hardening.nix
        ../modules/hyprland.nix
        ../modules/theming.nix
        ../modules/containers.nix
        ../modules/wazuh-manager.nix
        inputs.nix-gaming.nixosModules.pipewireLowLatency
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {
            inherit inputs;
            colors = import ../lib/colors.nix;
          };
          home-manager.sharedModules = [
            inputs.plasma-manager.homeModules.plasma-manager
            inputs.nix-index-database.homeModules.nix-index
          ];
          home-manager.users.stoleyy = import ../home/stoleyy;
        }
      ] ++ extraModules;
    };
}
