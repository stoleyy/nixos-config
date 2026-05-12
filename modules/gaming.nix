{ pkgs, ... }:

{
  programs.gamemode.enable  = true;
  programs.gamescope.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
  };

  environment.systemPackages = with pkgs; [
    mangohud
    protonup-qt
    heroic
    lutris
  ];
}
