# Helper factory for declaring NixOS hosts.
#
# Usage from flake.nix:
#   nixosConfigurations.predator = (import ./lib { inherit inputs; }).mkHost {
#     hostName = "predator";
#     extraModules = [ ./modules/nvidia.nix ];
#   };

{ inputs, ... }:

{
  mkHost =
    { hostName
    , system       ? "x86_64-linux"
    , extraModules ? [ ]
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
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
        inputs.nix-gaming.nixosModules.pipewireLowLatency
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs       = true;
          home-manager.useUserPackages     = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs    = { inherit inputs; };
          home-manager.users.stoleyy       = import ../home/stoleyy;
        }
      ] ++ extraModules;
    };
}
