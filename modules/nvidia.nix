# NVIDIA proprietary driver — production track, open=false (Ada workaround), VAAPI, Vulkan, modesetting.
# Also: LACT GPU monitor daemon, adaptive TDP timer.
{
  config,
  pkgs,
  host,
  ...
}:

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
    # extraPackages32: empty — nvidia-vaapi-driver has no 32-bit build.
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
    __GL_SHADER_DISK_CACHE_PATH = "${host.home}/.cache/nv-shader-cache";
    # Disable the driver's size limit. AAA titles (Cyberpunk, Hogwarts Legacy)
    # exceed the default cap; the driver then prunes old entries, causing
    # recompilation stutter. Well-documented fix (DXVK #4014, GamingOnLinux).
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
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

  # LACT — persistent GPU monitoring daemon (clocks, fans, power, temp history).
  # On NVIDIA: monitoring + CLI control; full undervolt/OC is AMD-only.
  services.lact.enable = true;

  # Adaptive TDP — poll GPU temp every 30 s, throttle power limit when hot.
  # RTX 4070 valid range: 100–200 W (nvidia-smi reports this). 200 W is stock
  # TDP; 160 W drops ~5% perf but keeps the GPU well under thermal throttle
  # on the G80SD's 4K@240Hz during extended sessions.
  systemd.services.nvidia-tdp = {
    description = "NVIDIA adaptive TDP (temp-reactive power limit)";
    after = [ "nvidia-persistenced.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nvidia-tdp" ''
        smi=/run/current-system/sw/bin/nvidia-smi
        temp=$($smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null || echo 0)
        if [ "$temp" -gt 75 ]; then
          $smi -pl 160
        else
          $smi -pl 200
        fi
      '';
    };
  };
  systemd.timers.nvidia-tdp = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
    };
  };
}
