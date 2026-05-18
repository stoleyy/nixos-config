{ pkgs, ... }:

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
          nv_powermizer_mode = 1; # force NVIDIA powermizer to max-perf while gaming
        };
      };
    };

    gamescope.enable = true;

    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      gamescopeSession.enable = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
      # Vetted nix-gaming SteamOS sysctl bundle: vm.max_map_count=2147483642
      # (fixes CS2/Hogwarts/DayZ/UE5 Proton crashes — default 65530 too low),
      # kernel.split_lock_mitigate=0, sched_cfs_bandwidth_slice_us,
      # tcp_fin_timeout. Module imported in lib/default.nix.
      platformOptimizations.enable = true;
      # Steam's CEF steamwebhelper GPU process hard-aborts inside the
      # pressure-vessel sandbox on this FHS-less NixOS box (cef_log
      # error_code=1002 → "GPU process isn't usable"; kernel: repeating
      # "trap int3 … in libcef.so" every ~10 s). Root cause: pressure-vessel
      # cannot map the host NVIDIA graphics provider into the container
      # (`Unable to determine architecture of provider / ldconfig`) — an
      # open upstream NixOS×pressure-vessel limitation with NO fix
      # (NixOS/nixpkgs#485863; GNU Guix steam-runtime#480).
      #
      # Exhaustively falsified on-box (do not retry): open=false (kernel
      # module irrelevant — retained for the separate Wayland crash-loop),
      # MESA_GLSL/SHADER_CACHE_DISABLE extraEnv, -cef-disable-gpu (ignored
      # by this client build), -cef-disable-sandbox, -no-cef-sandbox, Steam
      # Beta, GLCache/htmlcache wipes.
      #
      # -no-browser is the documented reliable endpoint (steam-for-linux
      # #8405): Steam runs in Small Mode (games list, launch/play, settings)
      # with the crashing CEF web UI disabled — no full store/library web
      # views. All games run 100 % NVIDIA-accelerated (separate processes /
      # their own per-game runtime, unaffected). Revisit / drop this when
      # NixOS/nixpkgs#485863 (pressure-vessel provider on FHS-less distros)
      # is fixed upstream.
      package = pkgs.steam.override {
        extraArgs = "-no-browser";
      };
    };
  };

  # System-wide auto nice/ionice/sched/oom tuning for ALL apps (browser,
  # compiles, media) via the CachyOS rule set. GameMode cedes renice/ioprio
  # (above) so they don't fight; GameMode keeps the governor swap + GPU power
  # state. cgroup_load uses BPF — fine on this non-hardened 6.12 kernel; set
  # false if the journal ever shows BPF/cgroup errors.
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

  environment.systemPackages = with pkgs; [
    mangohud
    heroic
    lutris
    wineWowPackages.stable
  ];
}
