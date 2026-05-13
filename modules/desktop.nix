{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # Plasma 6 Wayland is the default session; Hyprland stays available in the
  # SDDM session dropdown for occasional use.
  services.displayManager.defaultSession = "plasma";

  programs.kdeconnect.enable = true;

  environment.systemPackages = with pkgs; [
    kdePackages.plasma-browser-integration
  ];
}
