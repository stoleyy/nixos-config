{ theme, ... }:

let
  c = theme.colors;
in
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

        # Test a config without making it the boot default (reversible by reboot).
        tryrebuild = "sudo nixos-rebuild test --flake /etc/nixos#(hostname)";

        # Diff current running system vs what would be built.
        nixdiff = ''
          set new (nixos-rebuild build --flake /etc/nixos#(hostname) --no-link --print-out-paths 2>/dev/null)
          and nvd diff /run/current-system $new
        '';

        # Show closure size of the running system.
        nixsize = "nix path-info -Sh /run/current-system";

        # Garbage-collect old generations via nh (keeps last 3, or pass a number).
        nixgc = ''
          set keep (test (count $argv) -gt 0; and echo $argv[1]; or echo 3)
          sudo nh clean all --keep $keep
        '';

        # Quick systemd unit status — `svc nginx` or `svc` for all failed.
        svc = ''
          if test (count $argv) -eq 0
            systemctl --failed
          else
            systemctl status $argv[1]
            echo "---"
            journalctl -u $argv[1] -b 0 --no-pager -n 30
          end
        '';

        # Fuzzy-find and edit a nix file in the config.
        nixedit = ''
          set file (fd -e nix . /etc/nixos | fzf --preview "bat --color=always {}")
          and $EDITOR $file
        '';

        # Search NixOS options by keyword.
        nixopt = ''
          if test (count $argv) -eq 0
            echo "Usage: nixopt <keyword>"
            return 1
          end
          nixos-option -I nixpkgs=/etc/nixos 2>/dev/null \
            | rg -i $argv[1]; or man configuration.nix 2>/dev/null \
            | rg -i $argv[1]; or echo "Try: https://search.nixos.org/options?query=$argv[1]"
        '';

        # Port check — what's listening? `ports` or `ports 8080`.
        ports = ''
          if test (count $argv) -eq 0
            sudo ss -tlnp
          else
            sudo ss -tlnp | rg $argv[1]
          end
        '';

        # Quick git add-commit-push for /etc/nixos.
        nixpush = ''
          if test (count $argv) -eq 0
            echo "Usage: nixpush \"commit message\""
            return 1
          end
          cd /etc/nixos
          git add -A
          git commit -m $argv[1]
          git push
          cd -
        '';

        # Process search — `psg firefox`.
        psg = "ps aux | rg -v rg | rg $argv[1]";

        # Quick weather check.
        wttr = ''
          set loc (test (count $argv) -gt 0; and echo $argv[1]; or echo "")
          curl -s "wttr.in/$loc?format=3"
        '';

        # Extract any archive format.
        extract = ''
          if test (count $argv) -eq 0
            echo "Usage: extract <file>"
            return 1
          end
          switch $argv[1]
            case "*.tar.bz2"
              tar xjf $argv[1]
            case "*.tar.gz" "*.tgz"
              tar xzf $argv[1]
            case "*.tar.xz" "*.txz"
              tar xJf $argv[1]
            case "*.tar.zst"
              tar --zstd -xf $argv[1]
            case "*.zip"
              unzip $argv[1]
            case "*.7z"
              7z x $argv[1]
            case "*.rar"
              unrar x $argv[1]
            case "*.gz"
              gunzip $argv[1]
            case "*.bz2"
              bunzip2 $argv[1]
            case "*.xz"
              unxz $argv[1]
            case "*"
              echo "extract: unknown format '$argv[1]'"
              return 1
          end
        '';
      };
      interactiveShellInit = ''
        set -g fish_greeting ""
        colorscript random
      '';
    };

    starship = {
      enable = true;
      settings = {
        # Deltarune Sanctuary palette for prompt
        palette = "sanctuary";
        palettes.sanctuary = {
          fg = c.fg0;
          bg = c.bg0;
          inherit (c) green;
          inherit (c) yellow;
          inherit (c) blue;
          inherit (c) purple;
          inherit (c) aqua;
          inherit (c) orange;
          inherit (c) red;
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
        theme = "OneHalfDark";
        style = "numbers,changes";
      };
    };

    # Concise community-driven man page alternatives (`tldr tar`, `tldr git-rebase`).
    tealdeer = {
      enable = true;
      settings.updates.auto_update = true;
    };

    bash.enable = true;
  };
}
