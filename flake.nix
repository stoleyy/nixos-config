{
  description = "stoleyy's NixOS — Acer Predator (i7-13700K + RTX 4070), dual-boot with Windows";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }@inputs:
  let
    system = "x86_64-linux";
    mkHost = (import ./lib { inherit inputs; }).mkHost;
  in {
    nixosConfigurations.predator = mkHost {
      hostName = "predator";
      extraModules = [
        ./modules/nvidia.nix
        nixos-hardware.nixosModules.common-pc
        nixos-hardware.nixosModules.common-pc-ssd
        nixos-hardware.nixosModules.common-cpu-intel-cpu-only
        nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
      ];
    };

    formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
  };
}
