{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (tela-circle-icon-theme.override { colorVariants = [ "black" ]; })
    papirus-icon-theme
    bibata-cursors
    adw-gtk3
    kdePackages.qttools
    # Terminal audio visualizer — auto-attaches to the PipeWire default sink.
    cava
  ];

  fonts.packages = with pkgs; [
    inter
    nerd-fonts.geist-mono
  ];
}
