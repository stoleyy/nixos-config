# Hyprland session — the default SDDM session (autologin enabled).
{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Xwayland 24.1.10 + NVIDIA 580 + libepoxy 1.5.10 + glibc 2.40: the GBM
  # glamor EGL init path crashes (libepoxy's egl_provider_resolver calls
  # eglGetCurrentContext before any EGL display/context exists, aborting).
  # `-glamor off` disables the GPU-accelerated 2D path inside Xwayland;
  # 3D games (Proton/Vulkan) are unaffected — they bypass X11 rendering.
  # Revisit when libepoxy >= 1.5.11 or NVIDIA >= 590 ships a fix.
  programs.xwayland.package = pkgs.xwayland.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/Xwayland --add-flags "-glamor off"
    '';
  });

  # Required for hyprlock PAM authentication.
  security.pam.services.hyprlock = { };

  # Hyprland XDG portal merges with the KDE + GTK portals already declared in
  # modules/apps.nix (NixOS merges list-valued options across modules).
  xdg.portal = {
    extraPortals = with pkgs; [ xdg-desktop-portal-hyprland ];
    config.hyprland.default = [
      "hyprland"
      "gtk"
    ];
  };
}
