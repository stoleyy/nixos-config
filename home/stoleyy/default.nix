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
  ];

  home.username      = "stoleyy";
  home.homeDirectory = "/home/stoleyy";
  home.stateVersion  = "25.11";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    keepassxc
    tor-browser
    protonvpn-gui
  ];
}
