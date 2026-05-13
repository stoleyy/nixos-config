{ pkgs, ... }:

{
  imports = [
    ./shell.nix
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

  home.username = "stoleyy";
  home.homeDirectory = "/home/stoleyy";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  home.file.".local/share/color-schemes/BladeeBlack.colors".source = ./bladee-black.colors;

  home.packages = with pkgs; [
    keepassxc
    proton-pass
    tor-browser
    claude-code
  ];
}
