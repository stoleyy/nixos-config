# Nix daemon, binary caches, and developer UX (nh, direnv, fish shell integration).
_:

{
  nix = {
    settings = {
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Perf tuning: dedup the /nix/store + keep build outputs for faster incremental rebuilds.
      auto-optimise-store = true;
      keep-outputs = true;
      keep-derivations = true;

      # Cache resilience — prevent builds stalling on a downed substituter.
      # Nix's next-substituter fallback degrades on TCP-refused (NixOS/nix#6901);
      # a 5 s connect-timeout is mandatory mitigation for sometimes-on caches.
      connect-timeout = 5;
      fallback = true;
    };

    optimise = {
      automatic = true;
      dates = [ "03:45" ];
    };

    # Nix builds run at idle CPU scheduling — `nh os switch` doesn't block gaming/work.
    daemonCPUSchedPolicy = "idle";
  };

  programs = {
    nh = {
      enable = true;
      flake = "/etc/nixos";
      clean.enable = true;
      clean.extraArgs = "--keep-since 7d --keep 5";
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fish.enable = true;
    coolercontrol.enable = true;
    dconf.enable = true;

    # Local command-not-found via nix-index-database (HM module added in
    # lib/default.nix). Disables the deprecated nixpkgs CSV lookup.
    command-not-found.enable = false;
  };
}
