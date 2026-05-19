{ pkgs, ... }:
let
  # The only working Steam path on this box: the Windows steam.exe under
  # Wine. Native Linux Steam + Flatpak are blocked by the steamrt
  # pressure-vessel bug (nixpkgs#485863) — see docs/runbook.md and the
  # programs.steam note below. Fails loudly if the Vault drive isn't mounted.
  steam-wine = pkgs.writeShellScriptBin "steam-wine" ''
    set -euo pipefail
    steam_exe=/run/media/stoleyy/Vault/Steam/steam.exe
    if [ ! -e "$steam_exe" ]; then
      msg="Vault drive not mounted, or Steam missing at $steam_exe"
      ${pkgs.libnotify}/bin/notify-send -u critical -a 'Steam (Wine)' \
        'Steam cannot start' "$msg" 2>/dev/null || true
      echo "steam-wine: $msg" >&2
      exit 1
    fi
    exec ${pkgs.wineWowPackages.stable}/bin/wine "$steam_exe" "$@"
  '';
  steam-wine-desktop = pkgs.makeDesktopItem {
    name = "steam-wine";
    desktopName = "Steam (Wine)";
    comment = "Windows Steam under Wine — native Linux Steam blocked (nixpkgs#485863)";
    exec = "steam-wine %U";
    icon = "steam";
    categories = [ "Game" ];
    startupWMClass = "steam.exe";
  };
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
      # NOTE: the native nixpkgs Steam UI does NOT work on this box. Its CEF
      # steamwebhelper GPU process hard-aborts inside the pressure-vessel
      # sandbox because, on FHS-less NixOS, pressure-vessel cannot map the
      # host NVIDIA graphics provider into the container (cef_log
      # error_code=1002 → "GPU process isn't usable"; kernel: repeating
      # "trap int3 … in libcef.so"). Open upstream bug, no fix:
      # NixOS/nixpkgs#485863 / GNU Guix steam-runtime#480. Exhaustively
      # falsified on-box: open=false (kept for the separate Wayland
      # crash-loop), MESA_* extraEnv, -cef-disable-gpu (ignored),
      # -cef-disable-sandbox, -no-cef-sandbox, -no-browser, Beta, cache wipes.
      #
      # WORKING PATH: the Windows steam.exe under Wine (wineWowPackages
      # .stable) — see the `steam-wine` wrapper in this module's let block
      # and docs/runbook.md. Flatpak was also tried and fails identically
      # (same steamrt pressure-vessel). programs.steam.enable stays true
      # (no package override) for system gaming plumbing steam-wine /
      # controllers reuse: steam-hardware udev, Remote Play firewall, the
      # nix-gaming sysctl bundle, gamescope. Revert to the native client
      # only after nixpkgs#485863 is fixed upstream and proven on-box.
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
    steam-wine
    steam-wine-desktop
  ];
}
