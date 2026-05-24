{
  pkgs,
  lib,
  theme,
  ...
}:

let
  # Convert "#RRGGBB" to [R G B] integer list for Chromium theme JSON
  hexToRgb =
    hex:
    let
      h = builtins.substring 1 6 hex;
    in
    [
      (builtins.fromTOML "v=0x${builtins.substring 0 2 h}").v
      (builtins.fromTOML "v=0x${builtins.substring 2 2 h}").v
      (builtins.fromTOML "v=0x${builtins.substring 4 2 h}").v
    ];
  c = theme.colors;
in
{
  imports = [
    ./shell.nix
    ./ai.nix
    ./openhuman.nix
    ./claude-proxy.nix
    ./editor.nix
    ./browser.nix
    ./git.nix
    ./gpg.nix
    ./audio.nix
    ./hyprland.nix
    ./waybar.nix
    ./rofi.nix
    ./swaync.nix
    ./wlogout.nix
    ./gtk.nix
    ./plasma.nix
    ./spicetify.nix
    ./ghostty.nix
    ./mpv.nix
  ];

  home = {
    username = "stoleyy";
    homeDirectory = "/home/stoleyy";
    stateVersion = "25.11";

    file.".local/share/color-schemes/DeltaruneSanctuary.colors".source = ./deltarune-sanctuary.colors;

    # Brave/Chromium theme — Deltarune Sanctuary palette as an unpacked extension.
    # Load once: brave://extensions → Developer mode → Load unpacked → select this dir.
    file.".local/share/sanctuary-brave-theme/manifest.json".text = builtins.toJSON {
      manifest_version = 3;
      version = "1.0";
      name = "Deltarune Sanctuary";
      description = "Deep indigo theme matching the Deltarune Sanctuary palette";
      theme = {
        colors = {
          frame = hexToRgb c.bg1;
          frame_inactive = hexToRgb c.bg0;
          frame_incognito = hexToRgb c.bg2;
          frame_incognito_inactive = hexToRgb c.bg1;
          toolbar = hexToRgb c.bg1;
          toolbar_text = hexToRgb c.fg0;
          toolbar_button_icon = hexToRgb c.yellow;
          tab_background_text = hexToRgb c.fg2;
          tab_text = hexToRgb c.fg0;
          tab_selected = hexToRgb c.bg2;
          tab_background_inactive_frame = hexToRgb c.bg0;
          tab_background_inactive_frame_inactive = hexToRgb c.bg0;
          bookmark_text = hexToRgb c.fg1;
          ntp_background = hexToRgb c.bg0;
          ntp_text = hexToRgb c.fg0;
          ntp_link = hexToRgb c.yellow;
          ntp_header = hexToRgb c.bg1;
          omnibox_background = hexToRgb c.bg0;
          omnibox_text = hexToRgb c.fg0;
          omnibox_results_bg = hexToRgb c.bg1;
          omnibox_results_text = hexToRgb c.fg0;
          omnibox_results_url = hexToRgb c.yellow;
          button_background = hexToRgb c.green;
        };
        tints = {
          background_tab = [
            0.65
            0.5
            0.3
          ];
          buttons = [
            0.63
            0.6
            0.65
          ];
        };
      };
    };

    # Force-clear stale kdeglobals color cache. Plasma-manager declares
    # DeltaruneSanctuary but kdeglobals accumulates runtime color state
    # that overrides the declared scheme (right-click menus, Qt apps stay
    # Gruvbox yellow). Removing it lets plasma-manager write a clean copy.
    activation.fixKdeColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f "$HOME/.config/kdeglobals"
    '';

    # Pre-seed rofi drun cache so Ghostty appears first in Super+Space.
    activation.pinGhosttyInRofi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cache="$HOME/.cache/rofi3.druncache"
      entry="com.mitchellh.ghostty.desktop"
      mkdir -p "$(dirname "$cache")"
      if ! grep -q "$entry" "$cache" 2>/dev/null; then
        echo "100 $entry" >> "$cache"
      else
        ${pkgs.gnused}/bin/sed -i "s/^[0-9]* $entry$/100 $entry/" "$cache"
      fi
    '';

    packages = with pkgs; [
      qbittorrent
      keepassxc
      proton-pass
      tor-browser
      claude-code
      vesktop
      telegram-desktop
      protonmail-desktop
      dwt1-shell-color-scripts
    ];
  };

  programs.home-manager.enable = true;
}
