{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (tela-circle-icon-theme.override { colorVariants = [ "black" ]; })
    papirus-icon-theme
    bibata-cursors
    adw-gtk3
    kdePackages.qttools
    ghostty
    mpv
  ];

  fonts.packages = with pkgs; [
    inter
    nerd-fonts.geist-mono
  ];
}
