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
  ];

  home.username      = "stoleyy";
  home.homeDirectory = "/home/stoleyy";
  home.stateVersion  = "25.11";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    keepassxc
    proton-pass
    tor-browser
    protonvpn-gui
  ];
}
