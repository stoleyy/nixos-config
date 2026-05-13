# Hyprland session — set as SDDM default; Plasma 6 stays selectable as fallback.
{ lib, pkgs, ... }:

{
  programs.hyprland = {
    enable          = true;
    xwayland.enable = true;
  };

  # Hyprland default; Plasma stays selectable in SDDM's session dropdown.
  # mkForce guards against plasma6 (or any other module) also setting this.
  services.displayManager.defaultSession = lib.mkForce "hyprland";

  # Required for hyprlock PAM authentication.
  security.pam.services.hyprlock = { };

  # Hyprland XDG portal merges with the KDE + GTK portals already declared in
  # modules/apps.nix (NixOS merges list-valued options across modules).
  xdg.portal = {
    extraPortals            = with pkgs; [ xdg-desktop-portal-hyprland ];
    config.hyprland.default = [ "hyprland" "gtk" ];
  };
}
