# Hyprland session — selectable from SDDM; Plasma 6 is the default.
{ pkgs, ... }:

{
  programs.hyprland = {
    enable          = true;
    xwayland.enable = true;
  };

  # Required for hyprlock PAM authentication.
  security.pam.services.hyprlock = { };

  # Hyprland XDG portal merges with the KDE + GTK portals already declared in
  # modules/apps.nix (NixOS merges list-valued options across modules).
  xdg.portal = {
    extraPortals            = with pkgs; [ xdg-desktop-portal-hyprland ];
    config.hyprland.default = [ "hyprland" "gtk" ];
  };
}
