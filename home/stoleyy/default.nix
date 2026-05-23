{ pkgs, ... }:

{
  imports = [
    ./shell.nix
    ./ai.nix
    ./openhuman.nix
    ./claude-proxy.nix
    ./terminal.nix
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

    file.".local/share/color-schemes/GruvboxDarkHard.colors".source = ./gruvbox-dark-hard.colors;

    packages = with pkgs; [
      qbittorrent
      keepassxc
      proton-pass
      tor-browser
      claude-code
      vesktop
      telegram-desktop
    ];
  };

  programs.home-manager.enable = true;
}
