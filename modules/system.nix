# System health services: fstrim, fwupd, journald, OOM, CPU power tuning.
_:

{
  services = {
    # F-21: replace deprecated glibc nscd with memory-safe Rust nsncd
    nscd = {
      enable = true;
      enableNsncd = true;
    };

    # === Storage (NVMe) ===
    fstrim.enable = true;

    # Geolocation daemon — Plasma 6 NightLight `mode = "automatic"` (set in
    # home/stoleyy/plasma.nix) silently no-ops without geoclue's systemd unit;
    # KWin otherwise gets `geoclue.service not found` over DBus.
    geoclue2.enable = true;

    # Firmware updates via LVFS.
    fwupd.enable = true;

    journald.extraConfig = ''
      SystemMaxUse=2G
      MaxRetentionSec=1month
      Storage=persistent
      ForwardToSyslog=no
    '';
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # === Memory (64 GB) ===
  # /tmp in RAM — capped at 16 GB (default 50% = 32 GB is excessive).
  # Massive speedup for nix builds, archive extraction, compilations.
  # Replaces cleanOnBoot (tmpfs is wiped on every boot inherently).
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "16G";

  systemd = {
    # systemd-oomd watches cgroup memory pressure (PSI) and kills the worst
    # offender before the kernel OOM killer freezes the desktop for 10+ s.
    # 64 GB usually doesn't OOM, but Brave-with-200-tabs + Steam + a leaking
    # game can; this is the safety net. 20s pressure duration avoids transient
    # spikes triggering a kill.
    oomd = {
      enable = true;
      enableRootSlice = true;
      enableUserSlices = true;
      enableSystemSlice = true;
      settings.OOM.DefaultMemoryPressureDurationSec = "20s";
    };

    # File descriptor limits. systemd upstream default: 1024 soft / 524288 hard.
    # The old pattern of setting both to 1048576 was abandoned by Docker/Containerd
    # because programs iterating over all possible fds before fork/exec loop 1M
    # times (6.2s delay per subprocess in Python <3.10). 1024 soft also preserves
    # select() compatibility; apps that need more raise it themselves.
    settings.Manager.DefaultLimitNOFILE = "1024:524288";

    coredump.enable = false;

    # intel_pstate active mode: pin EPP=balance_performance (kernel HWP
    # default; set explicitly for determinism — best desktop burst + sustained
    # throughput, idle unaffected since HWP floors at min P-state) and enable
    # hwp_dynamic_boost (raises the min P-state on I/O wakeups → sub-ms ramp,
    # makes powersave feel identical to the perf governor for desktop bursts;
    # active+HWP only, no downside, sysfs-only — there is no module/boot param
    # for it). Gaming unaffected — GameMode's performance governor overrides
    # EPP in hardware while a game runs.
    services.cpu-power-tuning = {
      description = "CPU EPP + HWP dynamic boost (cold idle, snappy bursts)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          echo balance_performance > "$f" || true
        done
        echo 1 > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost || true
      '';
    };
  };

  system.stateVersion = "25.11";
}
