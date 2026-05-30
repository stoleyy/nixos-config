{ pkgs, theme, ... }:

let
  inherit (theme) colors;

  sanctuaryTheme = builtins.toFile "sanctuary.rasi" ''
    * {
      bg0:    ${colors.bg0}ff;
      bg1:    ${colors.bg1}ff;
      bg2:    ${colors.bg2}ff;
      fg0:    ${colors.fg0}ff;
      fg1:    ${colors.fg1}ff;
      accent: ${colors.blue}ff;

      background-color: transparent;
      text-color:       @fg0;
    }

    window {
      width:            50%;
      background-color: @bg0;
      border:           2px solid;
      border-color:     @accent;
      border-radius:    14px;
    }

    mainbox {
      background-color: transparent;
      children:         [ inputbar, listview ];
      spacing:          10px;
      padding:          16px;
    }

    inputbar {
      background-color: @bg1;
      border-radius:    10px;
      padding:          12px 16px;
      children:         [ prompt, entry ];
    }

    prompt {
      background-color: transparent;
      text-color:       @accent;
      padding:          0 8px 0 0;
    }

    entry {
      background-color:  transparent;
      text-color:        @fg0;
      placeholder:       "Type to search...";
      placeholder-color: @fg1;
    }

    listview {
      background-color: transparent;
      lines:            10;
      scrollbar:        true;
      spacing:          4px;
    }

    scrollbar {
      width:        4px;
      handle-width: 4px;
      handle-color: @bg2;
      border-radius: 2px;
    }

    element {
      padding:       10px 14px;
      border-radius: 8px;
      spacing:       12px;
    }

    element normal.normal {
      background-color: transparent;
      text-color:       @fg0;
    }

    element alternate.normal {
      background-color: transparent;
      text-color:       @fg0;
    }

    element selected.normal {
      background-color: @bg1;
      text-color:       @accent;
      border:           1px solid;
      border-color:     @accent;
    }

    element-text {
      background-color: transparent;
      text-color:       inherit;
      vertical-align:   0.5;
    }

    element-icon {
      size:             28px;
      background-color: transparent;
    }
  '';
in
{
  programs.rofi = {
    enable = true;
    # rofi-wayland was merged into rofi in nixpkgs 25.11 — unified package now
    # supports both X11 and Wayland backends; selection is automatic.
    package = pkgs.rofi;
    theme = sanctuaryTheme;
    extraConfig = {
      modi = "drun,run,window";
      icon-theme = "Papirus-Dark";
      show-icons = true;
      # Fuzzy matching with fzf-style ranking instead of strict prefix match.
      matching = "fuzzy";
      sort = true;
      sorting-method = "fzf";
      font = "${theme.font.name} ${toString theme.font.size}";
      drun-display-fmt = "{name}";
      display-drun = "  Apps";
      display-run = "  Run";
      display-window = "  Windows";
    };
  };
}
