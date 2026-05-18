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
      # CEF steamwebhelper crash-loop (cef_log error_code=1002 → "GPU
      # process isn't usable"). On NixOS pressure-vessel can't map the host
      # NVIDIA provider, so the in-container CEF GPU process falls back to
      # the runtime's Mesa ICD (llvmpipe); Mesa's GLSL path spawns threads,
      # tripping Chromium's single-threaded GPU-sandbox init. Disabling
      # Mesa's shader caches stops those pre-sandbox threads. extraEnv is
      # exported via the FHS /etc/profile and passes through pressure-vessel
      # into the CEF process. NVIDIA-only box → MESA_* is inert for native/
      # Proton games (NVIDIA GL/Vulkan) — games-safe. No upstream/nixpkgs
      # fix exists for the pressure-vessel provider failure (nixpkgs#485863).
      package = pkgs.steam.override {
        extraEnv = {
          MESA_GLSL_CACHE_DISABLE = "true";
          MESA_SHADER_CACHE_DISABLE = "true";
        };
        # extraEnv and -cef-disable-sandbox both insufficient on-box
        # (error_code=1002 ×41; libcef.so int3 abort persists). Trying the
        # alternate sandbox-disable spelling some client builds honour.
        # -cef-disable-gpu is proven ignored by this build. Local-only
        # desktop → CEF GPU process unsandboxed is an acceptable tradeoff.
        # Affects only the Steam client UI; game processes are separate.
        # If this also fails the next step is -no-browser (Small Mode).
        extraArgs = "-no-cef-sandbox";
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
