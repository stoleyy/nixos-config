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
          deadnix.enable = true; # dead-code — now enforced by `nix fmt` + `nix flake check`
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

      # Disaster recovery installer ISO — `nix build .#installer`
      # Boots with NetworkManager, SSH, sops, disko tools pre-installed.
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/predator/installer.nix ];
      };
      packages.${system}.installer =
        inputs.self.nixosConfigurations.installer.config.system.build.isoImage;

      # `nix fmt` — runs nixfmt + shfmt + statix in one pass.
      formatter.${system} = treefmtEval.config.build.wrapper;

      # `nix flake check` — catches unformatted/unlinted files.
      checks.${system}.formatting = treefmtEval.config.build.check inputs.self;

      # `nix run .#<app>` — operational commands as flake apps.
      # Discoverable via `nix flake show`.
      apps.${system} =
        let
          flakeRef = "/etc/nixos#predator";
          mkApp = name: script: {
            type = "app";
            program = toString (pkgs.writeShellScript name script);
          };
        in
        {
          rebuild = mkApp "rebuild" "sudo nixos-rebuild switch --flake ${flakeRef}";
          test = mkApp "test-config" "sudo nixos-rebuild test --flake ${flakeRef}";
          diff = mkApp "diff-config" ''
            new=$(nixos-rebuild build --flake ${flakeRef} --no-link --print-out-paths 2>/dev/null)
            ${pkgs.nvd}/bin/nvd diff /run/current-system "$new"
          '';
          gc = mkApp "gc" ''sudo ${pkgs.nh}/bin/nh clean all --keep "''${1:-3}"'';
          # Boot the whole config in a throwaway QEMU VM — exercises systemd
          # units / activation ordering without touching the real box. Catches
          # the unbootable-generation class that `flake check` + `dry-build`
          # cannot (e.g. the VMD/root-discovery brick from PR #13). Needs a
          # realized closure, so it is an on-box step, not part of the CI gate.
          vm = mkApp "vm" ''
            nixos-rebuild build-vm --flake ${flakeRef}
            echo "QEMU boot test built — run: ./result/bin/run-predator-vm"
          '';
          audit = mkApp "audit" ''
            echo "=== CVE scan (vulnix) ===" && ${pkgs.vulnix}/bin/vulnix -S 2>/dev/null || true
            echo "=== CVE scan (multi-engine: grype/osv/vulnix) ===" && ${pkgs.sbomnix}/bin/vulnxscan --buildtime /run/current-system 2>/dev/null || true
            echo "=== Secrets (patterns) ===" && ${pkgs.gitleaks}/bin/gitleaks detect --no-banner --no-git -s /etc/nixos 2>/dev/null || true
            echo "=== Secrets (verified) ===" && ${pkgs.trufflehog}/bin/trufflehog filesystem /etc/nixos --no-update --results=verified 2>/dev/null || true
            echo "=== Failed units ===" && systemctl --failed
            echo "=== Closure size ===" && nix path-info -Sh /run/current-system
          '';
        };

      # Local dev/lint harness. Enter with `nix develop`.
      # - Eval + LSP:     nixd, nil
      # - Format/lint:    nixfmt-rfc-style, statix, deadnix (all enforced via `nix fmt`)
      # - Closure tools:  nix-tree (deps), nix-diff (drv diff), nvd (generation diff)
      # - Search:         manix (option lookup)
      # - Build UX:       nix-output-monitor (logs), nix-fast-build (parallel eval gate)
      # - Derivations:    nixpkgs-hammering (packages/ antipattern lint)
      # - Security:       vulnix + sbomnix/vulnxscan (multi-engine CVE),
      #                   gitleaks + trufflehog (secrets), shellcheck
      devShells.${system}.default = pkgs.mkShell {
        # Pre-commit hook: install once with `nix develop`, then `install-hooks`.
        # Runs treefmt on staged files before each commit.
        shellHook = ''
          install-hooks() {
            mkdir -p .git/hooks
            cat > .git/hooks/pre-commit <<'HOOK'
          #!/bin/sh
          exec nix fmt 2>/dev/null
          HOOK
            chmod +x .git/hooks/pre-commit
            echo "Pre-commit hook installed."
          }
        '';
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
          nix-fast-build # parallel eval/build of flake outputs — fast whole-tree eval gate
          nixpkgs-hammering # derivation antipattern linter for packages/
          vulnix
          sbomnix # SBOM + `vulnxscan` (grype/osv/vulnix agreement-scored CVE)
          gitleaks
          trufflehog # verified secret scan (live-credential detectors) — complements gitleaks
          shellcheck
          flake-checker
          sops
          nurl # URL → fetchFromGitHub/fetchurl with correct hash
        ];
      };
    };
}
