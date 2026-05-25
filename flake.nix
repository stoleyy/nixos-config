{
  description = "stoleyy's NixOS — Acer Predator (i7-13700K + RTX 4070)";

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

    # Zen Browser — privacy-focused Firefox fork with vertical tabs.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Multi-language formatter — `nix fmt` runs nixfmt + shfmt in one pass;
    # `nix flake check` catches unformatted files.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
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
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (import ./lib { inherit inputs; }) mkHost;

      # treefmt: unified `nix fmt` for nix + shell files, with `nix flake check` integration.
      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true; # nixfmt-rfc-style
          shfmt.enable = true; # POSIX/Bash formatter
          statix.enable = true; # Nix linter/fixer
        };
      };
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

      # `nix fmt` — runs nixfmt + shfmt + statix in one pass.
      formatter.${system} = treefmtEval.config.build.wrapper;

      # `nix flake check` — catches unformatted/unlinted files.
      checks.${system}.formatting = treefmtEval.config.build.check inputs.self;

      # Local dev/lint harness. Enter with `nix develop`.
      # - Eval + LSP:     nixd, nil
      # - Format/lint:    nixfmt-rfc-style, statix, deadnix
      # - Closure tools:  nix-tree (deps), nix-diff (drv diff), nvd (generation diff)
      # - Search:         manix (option lookup)
      # - Build UX:       nix-output-monitor (pretty build logs)
      # - Security:       vulnix (CVE scan), gitleaks (secrets), shellcheck (hooks)
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixd
          nil
          nixfmt-rfc-style
          statix
          deadnix
          nix-tree
          nix-diff
          nix-output-monitor
          nvd
          manix
          vulnix
          gitleaks
          shellcheck
          flake-checker
          sops
          nurl # URL → fetchFromGitHub/fetchurl with correct hash
        ];
      };
    };
}
