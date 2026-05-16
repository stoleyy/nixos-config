{ pkgs, ... }:

{
  imports = [
    ./shell.nix
    ./ai.nix
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

    file.".local/share/color-schemes/BladeeBlack.colors".source = ./bladee-black.colors;

    packages = with pkgs; [
      keepassxc
      proton-pass
      tor-browser
      claude-code
    ];
  };

  programs.home-manager.enable = true;
}
