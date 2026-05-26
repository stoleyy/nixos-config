{
  pkgs,
  lib,
  theme,
  ...
}:

let
  inherit (theme) colors hexToRgb;
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
          frame = hexToRgb colors.bg1;
          frame_inactive = hexToRgb colors.bg0;
          frame_incognito = hexToRgb colors.bg2;
          frame_incognito_inactive = hexToRgb colors.bg1;
          toolbar = hexToRgb colors.bg1;
          toolbar_text = hexToRgb colors.fg0;
          toolbar_button_icon = hexToRgb colors.yellow;
          tab_background_text = hexToRgb colors.fg2;
          tab_text = hexToRgb colors.fg0;
          tab_selected = hexToRgb colors.bg2;
          tab_background_inactive_frame = hexToRgb colors.bg0;
          tab_background_inactive_frame_inactive = hexToRgb colors.bg0;
          bookmark_text = hexToRgb colors.fg1;
          ntp_background = hexToRgb colors.bg0;
          ntp_text = hexToRgb colors.fg0;
          ntp_link = hexToRgb colors.yellow;
          ntp_header = hexToRgb colors.bg1;
          omnibox_background = hexToRgb colors.bg0;
          omnibox_text = hexToRgb colors.fg0;
          omnibox_results_bg = hexToRgb colors.bg1;
          omnibox_results_text = hexToRgb colors.fg0;
          omnibox_results_url = hexToRgb colors.yellow;
          button_background = hexToRgb colors.green;
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
    # stale colors). Removing it lets plasma-manager write a clean copy.
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
      claude-code
      dwt1-shell-color-scripts
    ];
  };

  programs.home-manager.enable = true;
}
