{ config, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
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
    # open = false (proprietary module): the open kernel module is
    # unreliable for GPU init on THIS RTX 4070 (Ada) box — it crash-loops
    # the Plasma Wayland session / SDDM Wayland greeter (modules/desktop.nix)
    # AND fails the Steam CEF GPU process (cef_log: gpu_process_host.cc
    # error_code=1002 → "GPU process isn't usable"; upstream
    # ValveSoftware/steam-for-linux #9780/#10980/#11728, NVIDIA-tracked).
    # Proprietary is the mature Ada path and the documented fix for broken
    # NVIDIA GL/VA-API hw-accel. Revisit open=true only after a driver bump
    # proves these stay fixed on an on-box `nixos-rebuild test`.
    open = false;
    nvidiaSettings = true;

    powerManagement.enable = true;
    powerManagement.finegrained = false;

    # nvidia-persistenced keeps the GPU initialised across userspace sessions:
    # eliminates ~1 s GPU re-init on app launches, smooths suspend/resume,
    # and prevents rare GPU resets. Valuable on the proprietary module too.
    nvidiaPersistenced = true;

    # Production driver — best Wayland + Ada (RTX 4070) combination in 2025/26.
    # `production` lags `stable` by a few weeks but has stronger Wayland/HDR
    # validation. If a regression hits, fall back to `stable`.
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # nvidia-drm.fbdev=1 — required by kwin_wayland (Plasma 6) on NVIDIA 545+
  # to get a usable DRM framebuffer; modeset=1 alone (via
  # hardware.nvidia.modesetting.enable) is not sufficient and is a prime
  # suspect for the Plasma-Wayland crash-loop reverted in 59af7a7. Harmless
  # on the current X11 default session. Merges with boot.kernelParams from
  # base.nix / hardening.nix (NixOS concatenates list options).
  boot.kernelParams = [ "nvidia-drm.fbdev=1" ];

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # F11: MOZ_DISABLE_RDD_SANDBOX removed — disabling Firefox's RDD sandbox is a
    # security regression that was a workaround for older NVIDIA driver paths.
    # 560+ open kernel modules + nvidia-vaapi-driver 0.0.13+ no longer require it.
    # NIXOS_OZONE_WL is deliberately NOT set here: environment.sessionVariables
    # is session-agnostic, so a global value leaks a Wayland Ozone hint into the
    # default Plasma X11 session — a Chromium/CEF footgun (implicated in Steam's
    # steamwebhelper crash-loop). It is set in the Wayland path only, at
    # home/stoleyy/hyprland.nix.
    # G-Sync / VRR negotiation. Previously only set inside Hyprland's session
    # env (home/stoleyy/hyprland.nix) — under Plasma these were never present,
    # so VRR didn't actually engage for many GL/Vulkan games. Promoting to a
    # system session variable covers both sessions.
    __GL_GSYNC_ALLOWED = "1";
    __GL_VRR_ALLOWED = "1";
    # Free FPS win on the 4070 — driver-side multi-threaded GL command stream.
    __GL_THREADED_OPTIMIZATIONS = "1";
    # Persistent shader cache across runs — kills first-launch shader stutter
    # in big Vulkan/GL titles. Path defaults to ~/.nv when unset; pin it under
    # XDG_CACHE_HOME so it follows the user's cache hygiene.
    __GL_SHADER_DISK_CACHE = "1";
    __GL_SHADER_DISK_CACHE_PATH = "$HOME/.cache/nv-shader-cache";
  };

}
