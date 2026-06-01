# NVIDIA proprietary driver — production track, open=false (Ada workaround), VAAPI, Vulkan, modesetting.
# Also: LACT GPU monitor daemon, adaptive TDP timer.
{
  config,
  lib,
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
    # Cap pre-render queue to 1 frame — reduces input latency by ~4-8 ms at
    # 240 Hz. Slight throughput tradeoff but imperceptible at this refresh rate.
    __GL_MaxFramesAllowed = "1";
    # Prevent the driver from busy-waiting on vsync; uses usleep() instead,
    # freeing CPU cycles on the i7-13700K for game threads.
    __GL_YIELD = "USLEEP";
    # Force a synchronous GL-context handoff. With PrismLauncher's native-Wayland
    # GLFW (the ~8 fps fix — home/stoleyy/gaming.nix + packages/prism-gaming-setup.nix)
    # and earlyWindowControl=false, Minecraft/NeoForge creates its window via
    # NoVizFallback's multi-threaded GL-context handoff, which NVIDIA's Wayland EGL
    # aborts — "GLFW error 65544: EGL: Failed to clear current context" — crashing
    # window init in Minecraft.<init> before the game opens. Disabling threaded
    # optimisations makes the handoff synchronous and fixes it (verified in-game,
    # ATM10 300+ mods). Session-scoped here — NOT baked into a launcher wrapper —
    # so it reaches the Minecraft JVM no matter how PrismLauncher is started: the
    # launcher is single-instance (QLocalSocket), so a stale daemon would otherwise
    # spawn the JVM with the wrapper's env stripped. Only affects native OpenGL;
    # Proton/DXVK/VKD3D titles are Vulkan and unaffected.
    __GL_THREADED_OPTIMIZATIONS = "0";
    # Proton/DXVK/VKD3D pick a Vulkan device themselves; with the Intel iGPU
    # present they can land on it (low NVIDIA util, low FPS). Pin both to the
    # discrete card. Belt-and-suspenders with boot.blacklistedKernelModules
    # = ["i915"] in hardware.nix, but safe to keep even if i915 is absent.
    DXVK_FILTER_DEVICE_NAME = "NVIDIA";
    VKD3D_FILTER_DEVICE_NAME = "NVIDIA";
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

  # Adaptive GPU undervolt — clock lock + utilization/GameMode unlock + state cache.
  #
  # Three states, polled every 5 s (skips re-apply if unchanged):
  #   Gaming (flag OR util>50%): full clocks (210-3105), 200 W
  #     GameMode sets the flag-file; GPU utilization >50% catches Proton games
  #     where libgamemode.so is not visible inside the pressure-vessel container
  #     (steam-runtime#814) so the flag is never created. A 6-poll grace period
  #     (~30 s) prevents premature downclocking on momentary load drops.
  #   Normal (<75°C):            210-2100 MHz, 200 W — daily undervolt
  #   Hot    (≥75°C):            210-1800 MHz, 160 W — thermal safety net
  #
  # gaming-tuned specialisation overrides ExecStart with mkForce (always-unlocked).
  # RTX 4070 power range: 100-200 W. Clock range: 210-3105 MHz.
  systemd.services = {
    nvidia-undervolt =
      let
        smi = "/run/current-system/sw/bin/nvidia-smi";
        cache = "/tmp/nvidia-undervolt-state";
      in
      {
        description = "NVIDIA adaptive undervolt (clock lock + power limit)";
        wantedBy = [ "multi-user.target" ];
        after = [ "nvidia-persistenced.service" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = pkgs.writeShellScript "nvidia-undervolt" ''
            grace=0
            while true; do
              read -r temp util <<< \
                "$(${smi} --query-gpu=temperature.gpu,utilization.gpu \
                   --format=csv,noheader,nounits 2>/dev/null | tr ',' ' ')"
              temp=''${temp:-0}; util=''${util:-0}

              if [ -f "${host.gamemodeFlagFile}" ] || [ "''${util}" -gt 50 ]; then
                state=gaming; grace=6
              elif [ "''${grace}" -gt 0 ]; then
                state=gaming; grace=$((grace - 1))
              elif [ "''${temp}" -gt 75 ]; then
                state=hot
              else
                state=normal
              fi

              # Skip if state hasn't changed since last run.
              if [ "$state" != "$(cat ${cache} 2>/dev/null)" ]; then
                case $state in
                  gaming) ${smi} -rgc;          ${smi} -pl 200 ;;
                  hot)    ${smi} -lgc 210,1800; ${smi} -pl 160 ;;
                  normal) ${smi} -rgc;          ${smi} -pl 200 ;;
                esac
                echo "$state" > ${cache}
              fi

              sleep 5
            done
          '';
          Restart = "on-failure";
          RestartSec = "5s";
          # Bound the stop so shutdown can't stall on the systemd 90 s default if
          # an nvidia-smi call is wedged in a driver ioctl during GPU teardown.
          # Inherited by the gaming-tuned specialisation, which only mkForce's
          # ExecStart (sleep infinity) and leaves the rest of serviceConfig.
          TimeoutStopSec = "10s";
        };
      };
    # Timer removed — service runs its own poll loop.

    # Bound the stop timeout on the upstream GPU daemons too. Any of these can
    # hang during GPU teardown and otherwise force systemd to wait the full 90 s
    # default before SIGKILL — the source of the slow shutdown.
    nvidia-persistenced.serviceConfig.TimeoutStopSec = lib.mkForce "10s";
    lact.serviceConfig.TimeoutStopSec = lib.mkForce "10s";
  };
}
