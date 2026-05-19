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

    starship = {
      enable = true;
      settings = {
        # Gruvbox-warm palette for prompt
        palette = "gruvbox";
        palettes.gruvbox = {
          fg = "#ebdbb2";
          bg = "#1d2021";
          green = "#98971a";
          yellow = "#d79921";
          blue = "#458588";
          purple = "#b16286";
          aqua = "#689d6a";
          orange = "#d65d0e";
          red = "#cc241d";
        };
        format = "$directory$git_branch$git_status$nix_shell$character";
        right_format = "$cmd_duration";
        character = {
          success_symbol = "[❯](green)";
          error_symbol = "[❯](red)";
        };
        directory = {
          style = "bold yellow";
          truncation_length = 3;
          truncation_symbol = "…/";
        };
        git_branch = {
          format = "[$symbol$branch]($style) ";
          style = "purple";
          symbol = " ";
        };
        git_status = {
          format = "[$all_status$ahead_behind]($style) ";
          style = "orange";
        };
        nix_shell = {
          format = "[$symbol$state]($style) ";
          symbol = " ";
          style = "blue";
        };
        cmd_duration = {
          format = "[$duration]($style)";
          style = "fg:bg";
          min_time = 2000;
        };
      };
    };

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

    bat = {
      enable = true;
      config = {
        theme = "gruvbox-dark";
        style = "numbers,changes";
      };
    };

    bash.enable = true;
  };
}
