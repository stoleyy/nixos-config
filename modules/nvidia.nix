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
    # open = false (proprietary module): the open kernel module crash-loops
    # the Plasma Wayland session / SDDM Wayland greeter on this RTX 4070 (Ada)
    # box even with nvidia-drm.fbdev=1 — tested and confirmed broken on the
    # production driver (2026-05). Also breaks Steam CEF GPU process
    # (error_code=1002). Revisit only after a future driver bump on a spare
    # generation via nixos-rebuild test.
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
    # Persistent shader cache across runs — kills first-launch shader stutter
    # in big Vulkan/GL titles. The driver caches both OpenGL and Vulkan shaders
    # despite the "GL" prefix (confirmed NVIDIA forums + DXVK #4014). Path
    # pinned under XDG_CACHE_HOME for cache hygiene.
    __GL_SHADER_DISK_CACHE = "1";
    __GL_SHADER_DISK_CACHE_PATH = "/home/stoleyy/.cache/nv-shader-cache";
    # Disable the driver's size limit. AAA titles (Cyberpunk, Hogwarts Legacy)
    # exceed the default cap; the driver then prunes old entries, causing
    # recompilation stutter. Well-documented fix (DXVK #4014, GamingOnLinux).
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
    #
    # REMOVED (evidence-based audit):
    # - __GL_GSYNC_ALLOWED / __GL_VRR_ALLOWED: Hyprland controls VRR at the
    #   DRM/KMS level (misc:vrr). These OpenGL/GLX env vars can CONFLICT with
    #   the compositor's VRR management. Hyprland wiki recommends VRR_ALLOWED=0.
    # - __GL_THREADED_OPTIMIZATIONS: OpenGL-only. Irrelevant for Vulkan/DXVK
    #   (all Proton games). Can hurt perf or crash some titles (Phoronix).
    # - __GL_YIELD=USLEEP: Solves X11-era OpenGL compositor contention.
    #   Irrelevant on Wayland where Hyprland composites via Vulkan.
  };

  # PAT write-combining: ensures the driver uses Page Attribute Tables for
  # write-combining memory mappings instead of the MTRR fallback. On modern
  # kernels (6.x) this may already be handled, making it a harmless no-op.
  # Confirmed beneficial on some Intel CPUs (Arch forums: Kaby Lake PassMark
  # regression fixed). i7-13700K supports PAT.
  #
  # NVreg_InitializeSystemMemoryAllocations=0 REMOVED: breaks CUDA init
  # (NVIDIA DevForum confirmed), which impacts Ollama. The perf gain from
  # skipping a memset on GPU alloc is negligible (happens at load time, not
  # per-frame).
  boot.extraModprobeConfig = ''
    options nvidia NVreg_UsePageAttributeTable=1
  '';

}
