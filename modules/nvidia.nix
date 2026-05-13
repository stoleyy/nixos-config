{ pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable      = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      nvidia-vaapi-driver
      libva
      libvdpau-va-gl
    ];
    # F12: pkgsi686Linux.nvidia-vaapi-driver removed — package has no 32-bit build,
    # would block predator evaluation. extraPackages32 left empty for future 32-bit deps.
    extraPackages32 = [ ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open               = true;
    nvidiaSettings     = true;

    powerManagement.enable      = true;
    powerManagement.finegrained = false;
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME         = "nvidia";
    NVD_BACKEND               = "direct";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # F11: MOZ_DISABLE_RDD_SANDBOX removed — disabling Firefox's RDD sandbox is a
    # security regression that was a workaround for older NVIDIA driver paths.
    # 560+ open kernel modules + nvidia-vaapi-driver 0.0.13+ no longer require it.
    NIXOS_OZONE_WL            = "1";
    # G-Sync / VRR negotiation. Previously only set inside Hyprland's session
    # env (home/stoleyy/hyprland.nix) — under Plasma these were never present,
    # so VRR didn't actually engage for many GL/Vulkan games. Promoting to a
    # system session variable covers both sessions.
    __GL_GSYNC_ALLOWED          = "1";
    __GL_VRR_ALLOWED            = "1";
    # Free FPS win on the 4070 — driver-side multi-threaded GL command stream.
    __GL_THREADED_OPTIMIZATIONS = "1";
    # Persistent shader cache across runs — kills first-launch shader stutter
    # in big Vulkan/GL titles. Path defaults to ~/.nv when unset; pin it under
    # XDG_CACHE_HOME so it follows the user's cache hygiene.
    __GL_SHADER_DISK_CACHE      = "1";
    __GL_SHADER_DISK_CACHE_PATH = "$HOME/.cache/nv-shader-cache";
  };

  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
  ];
}
