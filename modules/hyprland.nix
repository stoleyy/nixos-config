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
  # `-glamor off` disables the GPU-accelerated 2D path inside Xwayland.
  #
  # CAVEAT — this is NOT free for games (an earlier version of this comment
  # wrongly claimed "3D games are unaffected"). Disabling glamor also kills
  # XWayland's accelerated DRI3 present, so Vulkan/DXVK frames are copied to
  # the X11 window on the CPU — catastrophic at 4K (~8 fps, GPU idle). Proton
  # games therefore present via native Wayland (PROTON_ENABLE_WAYLAND=1 in
  # modules/gaming.nix), bypassing XWayland entirely. Native X11 2D apps stay
  # software-composited, which is imperceptible for normal use.
  # Revisit (drop `-glamor off`) once libepoxy/NVIDIA ship a fix and the crash
  # no longer reproduces from a clean `nixos-rebuild test`.
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
