{ pkgs, colors, ... }:

let
  gruvboxTheme = builtins.toFile "gruvbox-hard.rasi" ''
    * {
      bg0:    ${colors.bg0}ff;
      bg1:    ${colors.bg1}ff;
      fg0:    ${colors.fg0}ff;
      fg1:    ${colors.fg1}ff;
      accent: ${colors.green}ff;

      background-color: transparent;
      text-color:       @fg0;
    }

    window {
      width:            42%;
      background-color: @bg0;
      border:           2px solid;
      border-color:     @accent;
      border-radius:    12px;
    }

    mainbox {
      background-color: transparent;
      children:         [ inputbar, listview ];
      spacing:          8px;
      padding:          12px;
    }

    inputbar {
      background-color: @bg1;
      border-radius:    8px;
      padding:          10px 12px;
      children:         [ prompt, entry ];
    }

    prompt {
      background-color: transparent;
      text-color:       @accent;
      padding:          0 6px 0 0;
    }

    entry {
      background-color:  transparent;
      text-color:        @fg0;
      placeholder:       "Search...";
      placeholder-color: @fg1;
    }

    listview {
      background-color: transparent;
      lines:            8;
      scrollbar:        false;
    }

    element {
      padding:       8px 10px;
      border-radius: 6px;
    }

    element normal.normal {
      background-color: transparent;
      text-color:       @fg0;
    }

    element selected.normal {
      background-color: @bg1;
      text-color:       @accent;
    }

    element-text {
      background-color: transparent;
      text-color:       inherit;
      vertical-align:   0.5;
    }

    element-icon {
      size:             24px;
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
    theme = gruvboxTheme;
    extraConfig = {
      modi = "drun,run,window";
      icon-theme = "Papirus-Dark";
      show-icons = true;
      font = "JetBrainsMono Nerd Font 12";
      drun-display-fmt = "{name}";
      display-drun = "  Apps";
      display-run = "  Run";
      display-window = "  Windows";
    };
  };
}
