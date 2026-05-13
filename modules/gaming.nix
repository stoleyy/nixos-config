{ pkgs, ... }:

{
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        renice              = 10;     # gamemoderun'd process gets a priority boost
        inhibit_screensaver = 1;
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        nv_powermizer_mode      = 1;  # force NVIDIA powermizer to max-perf while gaming
      };
    };
  };

  programs.gamescope.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
  };

  environment.systemPackages = with pkgs; [
    mangohud
    heroic
    lutris
  ];
}
