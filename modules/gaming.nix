# Steam, GameMode, gamescope, ananicy-cpp, and the game-install torrent pipeline.
{ pkgs, host, ... }:

let
  gameInstall = pkgs.callPackage ../packages/game-install.nix { inherit host; };
in

{
  programs = {
    gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 0; # ananicy owns nice (was 10; would fight ananicy)
          ioprio = "off"; # ananicy owns ionice ("off" disables; 0 = highest!)
          inhibit_screensaver = 1;
          # Full boost while a game runs. No defaultgov on purpose → GameMode
          # restores the PRE-game governor, which is correctly "powersave" in
          # the secure default boot and "performance" in the gaming-tuned
          # specialisation. (softrealtime omitted — SCHED_ISO is a no-op on
          # mainline/nixpkgs 6.12; the -ck patch was never upstreamed.)
          desiredgov = "performance";
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          # card1 = NVIDIA RTX 4070. simpledrm occupies card0 briefly at boot
          # (fbdev=1 replaces it but the minor stays allocated); i915 is
          # blacklisted (hardware.nix) so NVIDIA is the only GPU card.
          # nv_powermizer_mode fails silently on NVIDIA proprietary (sysfs GPU
          # tuning is AMD-only); the nvidia-undervolt util-based IPC in
          # `custom` below is the actual GPU unlock mechanism.
          device = 1;
          nv_powermizer_mode = 1;
        };
        # GPU clock unlock: signal the nvidia-undervolt timer (modules/nvidia.nix)
        # to release the clock lock while gaming. The timer picks up the flag
        # within 15 s and unlocks full boost (210-3105 MHz).
        # No sudo needed — the flag file is the only IPC.
        custom = {
          start = "${pkgs.coreutils}/bin/touch ${host.gamemodeFlagFile}";
          end = "${pkgs.coreutils}/bin/rm -f ${host.gamemodeFlagFile}";
        };
      };
    };

    gamescope = {
      enable = true;
      # Grant CAP_SYS_NICE so gamescope can renice its threads for realtime
      # scheduling. Without this, the gaming-tuned greetd session logs
      # "No CAP_SYS_NICE, falling back to regular-priority compute and threads."
      capSysNice = true;
    };

    steam = {
      enable = true;
      # Opens UDP 27031-27036 + TCP 27036-27037 for Steam Remote Play (LAN streaming).
      # These ports are automatically managed by the Steam NixOS module.
      remotePlay.openFirewall = true;
      gamescopeSession.enable = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
      # Inject gamemode into Steam's FHS sandbox so libgamemode.so is visible
      # to games launched via `gamemoderun %command%` in Steam launch options.
      package = pkgs.steam.override {
        extraPkgs = p: [ p.gamemode ];
        # Force Mesa software rendering for Steam's CEF UI (steamwebhelper).
        # Without this, the CEF GPU process tries NVIDIA OpenGL inside the
        # steam runtime container and hits glibc ABI incompatibilities
        # (__malloc_hook removed in glibc 2.34+), causing steamwebhelper to
        # never serve its IPC websocket → Steam times out → "Failed to connect
        # to websocket" / crash. Games still use NVIDIA via Vulkan/Proton.
        extraEnv = {
          LIBGL_ALWAYS_SOFTWARE = "1";
          __GLX_VENDOR_LIBRARY_NAME = "mesa";
        };
        # Steam 1779918128+ fixed browser_subprocess_path in CEF — no LD_PRELOAD hack
        # needed. Gamemode for games is handled by gamemoderun via launch options or
        # the libgamemodeauto.so.0 that gamemode adds to the FHS env (extraPkgs above).
      };
      # Vetted nix-gaming SteamOS sysctl bundle: vm.max_map_count=2147483642
      # (fixes CS2/Hogwarts/DayZ/UE5 Proton crashes — default 65530 too low),
      # kernel.split_lock_mitigate=0, sched_cfs_bandwidth_slice_us,
      # tcp_fin_timeout. Module imported in lib/default.nix.
      platformOptimizations.enable = true;
    };
  };

  # System-wide auto nice/ionice/sched/oom tuning for ALL apps (browser,
  # compiles, media) via the CachyOS rule set. GameMode cedes renice/ioprio
  # (above) so they don't fight; GameMode keeps the governor swap + GPU power
  # state. cgroup_load uses BPF — ananicy-cpp runs as root (systemd service),
  # so kernel.unprivileged_bpf_disabled=1 (hardening.nix) does NOT block it;
  # only unprivileged BPF is restricted. Set false if the journal ever shows
  # BPF/cgroup errors from ananicy.
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
    settings = {
      check_freq = 5;
      cgroup_load = true;
      apply_nice = true;
      apply_ioclass = true;
      apply_ionice = true;
      apply_sched = true;
      apply_oom_score_adj = true;
    };
  };

  environment.sessionVariables = {
    # Suppress Wine's verbose debug logging — measurable overhead for zero
    # diagnostic value during normal gameplay. Arch Wiki gaming page standard.
    WINEDEBUG = "-all";

    # Present Proton games directly to Wayland instead of through XWayland.
    # The Hyprland session runs Xwayland with `-glamor off` (a libepoxy/NVIDIA
    # crash workaround — see modules/hyprland.nix), which also disables
    # XWayland's accelerated DRI3 present. DXVK frames then get copied to the
    # X11 window on the CPU; at 4K that ~33 MB/frame copy dominates the frame
    # time, so the GPU renders instantly then idles and the game crawls (~8 fps
    # with the GPU at <20% / 40 W). Native Wayland present bypasses XWayland
    # entirely and restores full performance. Override per-title with
    # `PROTON_ENABLE_WAYLAND=0 %command%` if a game misbehaves under it.
    PROTON_ENABLE_WAYLAND = "1";
  };

  # Create the tmpfs dir for the GameMode IPC flag file at boot.
  # /run is tmpfs — this directory must exist before gamemode starts a game.
  systemd.tmpfiles.rules = [ "d /run/gamemode 0755 ${host.user} users -" ];

  environment.systemPackages = with pkgs; [
    gameInstall
    mangohud
    # lutris: run on-demand via `nix run nixpkgs#lutris` (4.6 GiB savings)
    prismlauncher
    adwsteamgtk
    (callPackage ../packages/greenlight.nix { })
  ];

  environment.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT = "auto";
}
