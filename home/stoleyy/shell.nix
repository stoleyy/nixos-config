_:

{
  programs = {
    fish = {
      enable = true;
      shellAliases = {
        ll = "eza -la --git";
        nb = "nh os switch";
        cat = "bat";
        grep = "rg";
      };
      # F-24 (v2): aliases can't reliably hold (hostname) substitution in fish.
      # Define `rebuild` as a function so command substitution evaluates at runtime.
      functions = {
        rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#(hostname)";
      };
      interactiveShellInit = "set -U fish_greeting";
    };

    starship.enable = true;

    # Modern CLI replacements. `z <dir>` (zoxide) frecency-jumps; Ctrl-R (fzf)
    # fuzzy-searches history (atuin wins under fish but fzf adds file pickers);
    # `eza` powers the retargeted `ll` alias above.
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
    fzf = {
      enable = true;
      enableFishIntegration = true;
    };
    eza = {
      enable = true;
      enableFishIntegration = true;
      icons = "auto";
    };

    atuin = {
      enable = true;
      enableFishIntegration = true;
      settings = {
        auto_sync = false;
        update_check = false;
      };
    };

    # Local command index, fed by the pre-built database from
    # nix-index-database (flake input, wired in lib/default.nix). `comma`
    # gives a one-shot `, <cmd>` wrapper.
    nix-index.enable = true;
    nix-index-database.comma.enable = true;

    bash.enable = true;
  };
}
