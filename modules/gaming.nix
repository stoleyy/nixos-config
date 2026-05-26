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
          # card1 = NVIDIA RTX 4070; card0 = simpledrm (no vendor file).
          # Without this, GameMode tries card0 and logs:
          # "Couldn't open vendor file at /sys/class/drm/card0/device/vendor"
          device = 1;
          nv_powermizer_mode = 1; # force NVIDIA powermizer to max-perf while gaming
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
      remotePlay.openFirewall = true;
      gamescopeSession.enable = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
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

  # Suppress Wine's verbose debug logging — measurable overhead for zero
  # diagnostic value during normal gameplay. Arch Wiki gaming page standard.
  environment.sessionVariables.WINEDEBUG = "-all";

  environment.systemPackages = with pkgs; [
    gameInstall
    mangohud
    # lutris: run on-demand via `nix run nixpkgs#lutris` (4.6 GiB savings)
    prismlauncher
    adwsteamgtk
  ];
}
