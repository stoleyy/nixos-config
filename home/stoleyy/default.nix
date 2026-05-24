{ pkgs, lib, ... }:

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
          # Browser frame (titlebar area)
          frame = [
            7
            6
            47
          ]; # bg1
          frame_inactive = [
            0
            0
            0
          ]; # bg0
          frame_incognito = [
            10
            9
            78
          ]; # bg2
          frame_incognito_inactive = [
            7
            6
            47
          ];

          # Toolbar / URL bar
          toolbar = [
            7
            6
            47
          ]; # bg1
          toolbar_text = [
            200
            202
            224
          ]; # fg0
          toolbar_button_icon = [
            89
            135
            198
          ]; # blue

          # Tabs
          tab_background_text = [
            141
            143
            167
          ]; # muted
          tab_text = [
            200
            202
            224
          ]; # fg0

          # Active tab
          tab_selected = [
            10
            9
            78
          ]; # bg2

          # Background tabs
          tab_background_inactive_frame = [
            0
            0
            0
          ];
          tab_background_inactive_frame_inactive = [
            0
            0
            0
          ];

          # Bookmark bar
          bookmark_text = [
            178
            181
            207
          ]; # fg1

          # New tab page
          ntp_background = [
            0
            0
            0
          ]; # bg0
          ntp_text = [
            200
            202
            224
          ]; # fg0
          ntp_link = [
            89
            135
            198
          ]; # blue
          ntp_header = [
            7
            6
            47
          ]; # bg1

          # Omnibox (URL bar)
          omnibox_background = [
            0
            0
            0
          ]; # bg0
          omnibox_text = [
            200
            202
            224
          ]; # fg0
          omnibox_results_bg = [
            7
            6
            47
          ]; # bg1
          omnibox_results_text = [
            200
            202
            224
          ]; # fg0
          omnibox_results_url = [
            89
            135
            198
          ]; # blue

          # Button background
          button_background = [
            60
            75
            155
          ]; # accent
        };
        tints = {
          # Tint inactive tabs toward dark indigo
          background_tab = [
            0.65
            0.5
            0.3
          ];
          # Buttons keep accent hue
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
