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

  # nerd-fonts.jetbrains-mono lives in modules/fonts.nix (single source)
  fonts.packages = with pkgs; [
    inter
    nerd-fonts.geist-mono
  ];
}
