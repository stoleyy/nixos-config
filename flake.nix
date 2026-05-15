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

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pre-built nix-index database — `nix-locate` + `,` wrapper without the
    # multi-minute local index build.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative secrets management — encrypts with the host SSH Ed25519 key
    # (auto-converted to age format). Ciphertext commits safely to git.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixos-hardware,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      inherit ((import ./lib { inherit inputs; })) mkHost;
    in
    {
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

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;

      # Local dev/lint harness. Enter with `nix develop`.
      # - Eval + LSP:     nixd, nil
      # - Format/lint:    nixfmt-rfc-style, statix, deadnix
      # - Closure tools:  nix-tree (deps), nvd (generation diff)
      # - Security:       vulnix (CVE scan), gitleaks (secrets), shellcheck (hooks)
      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = with nixpkgs.legacyPackages.${system}; [
          nixd
          nil
          nixfmt-rfc-style
          statix
          deadnix
          nix-tree
          nvd
          vulnix
          gitleaks
          shellcheck
        ];
      };
    };
}
