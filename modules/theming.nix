{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    papirus-icon-theme
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
