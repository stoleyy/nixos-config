{ pkgs, config, ... }:

{
  nix = {
    settings = {
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      max-jobs = "auto";
      cores = 0;
      # Perf tuning: dedup the /nix/store + keep build outputs for faster incremental rebuilds.
      auto-optimise-store = true;
      keep-outputs = true;
      keep-derivations = true;
    };

    optimise = {
      automatic = true;
      dates = [ "03:45" ];
    };

    # Nix builds run at idle CPU scheduling — `nh os switch` doesn't block gaming/work.
    daemonCPUSchedPolicy = "idle";
  };

  programs = {
    # Foreign (non-Nix) ELF binaries run via nix-ld. Defining `libraries`
    # REPLACES the upstream module default, so its default set is re-listed
    # below and then the Chromium/CEF runtime closure is added: prebuilt
    # Electron/CEF apps (e.g. openhuman) otherwise FATAL on a runtime dlopen
    # of libsoftokn3.so because nss/nspr aren't on the default nix-ld path.
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # --- nix-ld upstream defaults (re-listed: definition replaces default) ---
        zlib
        zstd
        stdenv.cc.cc
        curl
        openssl
        attr
        libssh
        bzip2
        libxml2
        acl
        libsodium
        util-linux
        xz
        systemd
        # --- NSS / NSPR: the fatal libsoftokn3.so dlopen ---
        nss
        nspr
        # --- glib / GTK stack ---
        glib
        gtk3
        gdk-pixbuf
        pango
        cairo
        atk
        at-spi2-atk
        at-spi2-core
        # --- IPC / printing ---
        dbus
        cups
        # --- graphics ---
        libdrm
        libgbm
        mesa
        libGL
        vulkan-loader
        expat
        libxkbcommon
        fontconfig
        freetype
        # --- audio ---
        alsa-lib
        libpulseaudio
        # --- X11 ---
        xorg.libX11
        xorg.libXcomposite
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXrandr
        xorg.libXrender
        xorg.libXtst
        xorg.libXi
        xorg.libXcursor
        xorg.libXScrnSaver
        xorg.libxcb
        xorg.libXau
        xorg.libXdmcp
        libxshmfence
      ];
    };

    nh = {
      enable = true;
      flake = "/etc/nixos";
      clean.enable = true;
      clean.extraArgs = "--keep-since 7d --keep 5";
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fish.enable = true;
    coolercontrol.enable = true;
    dconf.enable = true;

    # Local command-not-found via nix-index-database (HM module added in
    # lib/default.nix). Disables the deprecated nixpkgs CSV lookup.
    command-not-found.enable = false;
  };

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
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  console.keyMap = "us";

  boot = {
    # === Kernel ===
    # Plain pkgs.linuxPackages = Linux 6.12.87 on this nixpkgs commit, which is
    # the same kernel gen 2 boots cleanly on. linuxPackages_lts was removed from
    # this nixpkgs (only linuxPackages_6_<N> versioned packages exist).
    #
    # Why not a 7.x kernel: NVIDIA 580.x (production) is incompatible with
    # Linux 7.0 — kernel 7.0 removed VMA_LOCK_OFFSET / changed __is_vma_write_locked()
    # in mmap_lock.h. The NVIDIA module then silently panics in the initrd before
    # any console is established. Confirmed on zen 7.0.3-zen1 and mainline 7.0.5.
    # No nixpkgs NVIDIA driver reliably handles kernel 7.x yet (590 fails on 6.19+).
    # Revisit when NVIDIA ships a driver that cleanly supports kernel 7.x.
    # Ref: NVIDIA/open-gpu-kernel-modules#1113
    kernelPackages = pkgs.linuxPackages;

    # chipsec.ko — userspace CLI added to environment.systemPackages below.
    # `sudo chipsec_util spi dump` / `sudo chipsec_main` for platform security
    # and firmware diagnostics. Module is built against the running kernel.
    extraModulePackages = [ config.boot.kernelPackages.chipsec ];

    # Stop Linux throttling Proton games that trip split-lock atomics.
    # Merges with the NVIDIA DRM params declared in modules/nvidia.nix.
    # split_lock_mitigate=0 is handled by nix-gaming's platformOptimizations
    # sysctl (keeps the detector + dmesg warning, removes the 10ms penalty).
    #
    # transparent_hugepage=always: Wine/Proton do NOT call madvise(MADV_HUGEPAGE)
    # (Valve Proton #5816), so `madvise` gives games zero THP benefit. `always`
    # with defrag=defer+madvise (tmpfiles rule below) provides 2-7% FPS gains
    # (Phoronix THP benchmarks) without synchronous compaction stalls.
    #
    # preempt=full: PREEMPT_DYNAMIC (6.12) makes this zero-cost. Lower
    # frame-time variance + snappier UI. Liquorix/gaming distro default.
    kernelParams = [
      "transparent_hugepage=always"
      "preempt=full"
    ];

    # === Memory (64 GB) ===
    # /tmp in RAM — capped at 16 GB (default 50% = 32 GB is excessive).
    # Massive speedup for nix builds, archive extraction, compilations.
    # Replaces cleanOnBoot (tmpfs is wiped on every boot inherently).
    tmp.useTmpfs = true;
    tmp.tmpfsSize = "16G";

    kernel.sysctl = {
      # With zram, swapping is in-memory — faster than NVMe filesystem I/O.
      # Kernel docs (5.8+, 0–200 range): values >100 weight anonymous-page
      # reclaim higher than file-cache eviction, which is correct when swap is
      # RAM-backed. 180 proactively compresses cold anonymous pages (idle
      # browser tabs, backgrounded game allocations) into zram, keeping page
      # cache warm for active I/O. Validated by Arch Wiki, Pop!_OS, Fedora,
      # and kernel vm.txt. page-cluster=0 disables swap readahead — pointless
      # for random-access compressed RAM (Pop!_OS/Android/ChromeOS default).
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
      "vm.vfs_cache_pressure" = 50; # Keep dentry/inode cache around longer
      "net.core.default_qdisc" = "fq"; # Pair with BBR
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_fastopen" = 1; # TFO client-only; server bit is dead weight on a desktop
      # Preserve cwnd across idle periods (RFC 2861). Without this, every
      # connection that idles for one RTO resets to initial window. fq qdisc
      # already paces packets, mitigating the theoretical burst concern.
      # Google/Cloudflare/CachyOS default.
      "net.ipv4.tcp_slow_start_after_idle" = 0;
      # Auto-enable MTU probing when an ICMP black hole is detected. Many ISPs
      # drop "fragmentation needed" packets; this prevents connections from
      # stalling at the wrong MTU. Purely reactive, zero overhead otherwise.
      "net.ipv4.tcp_mtu_probing" = 1;
      # Reduce TCP send-buffer bloat — report writability only when unsent data
      # drops below 128 KB. macOS default. Reduces latency for multiplayer and
      # streaming with no throughput cost at desktop scale.
      "net.ipv4.tcp_notsent_lowat" = 131072;
      # TCP buffer maximums for 1 Gbps+. Kernel auto-tunes per connection;
      # these are ceilings, memory allocated only when needed. ESnet/Google ref.
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_rmem" = "4096 131072 16777216";
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";
      # Per-CPU packet receive queue. Default 1000 can overflow on gigabit
      # bursts. 4096 is the CachyOS/standard recommendation for 1Gbps; 16384
      # is 10GbE-level overkill. Check /proc/net/softnet_stat col 2 for drops.
      "net.core.netdev_max_backlog" = 4096;

      # === Dirty page writeback (gaming / repack installs) ===
      # Kernel defaults (~20% of RAM = ~12.8 GB dirty ceiling on 64 GB) let
      # too much dirty data accumulate before flushing, causing latency spikes.
      # Absolute byte limits trigger writeback sooner & more predictably.
      # CachyOS reference values.
      "vm.dirty_bytes" = 268435456; # 256 MB
      "vm.dirty_background_bytes" = 67108864; # 64 MB

      # === Memory management latency reduction (CachyOS / Arch Wiki gaming) ===
      # Disable proactive compaction — kcompactd handles on-demand via
      # defer+madvise THP defrag (tmpfiles rule below).
      "vm.compaction_proactiveness" = 0;
      # Minimize watermark boosting — reduces unnecessary page reclaim.
      "vm.watermark_boost_factor" = 1;
      # Page lock fairness. Kernel default of 5 was chosen via Phoronix
      # benchmarks (Linux 5.9); values 4-5 outperformed both 1 and 1000.
      "vm.page_lock_unfairness" = 5;
      # Writeback thread wake interval. With explicit dirty_bytes thresholds,
      # the threads don't need to wake every 5 s (default 500). 15 s reduces
      # unnecessary NVMe write wakeups. CachyOS default.
      "vm.dirty_writeback_centisecs" = 1500;
      # Disable NMI hard-lockup detector — debugging feature that generates
      # periodic non-maskable interrupts. Only useful for kernel development.
      # CachyOS/Fedora/Ubuntu all disable on desktops.
      "kernel.nmi_watchdog" = 0;
      # ananicy-cpp uses cgroups directly, superseding autogroup's TTY-based
      # grouping. With autogroup on, game + Wine/Proton + DXVK shader threads
      # share one scheduling group while idle terminals get equal share.
      # CachyOS disables autogroup when ananicy is active.
      "kernel.sched_autogroup_enabled" = 0;
    };
  };

  # THP defrag: defer+madvise defers hugepage compaction to a background
  # kcompactd thread instead of doing it synchronously in the allocating
  # process, preventing allocation stalls during gameplay. CachyOS default.
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise"
  ];

  # NVMe I/O scheduler: `none` is optimal — NVMe devices have internal
  # multi-queue scheduling; the kernel's software scheduler adds overhead.
  # Phoronix benchmarks confirm `none` wins on NVMe for random I/O.
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
  '';

  hardware = {
    # === CPU (i7-13700K) ===
    # Raptor Lake degradation patches + perf microcode.
    cpu.intel.updateMicrocode = true;

    # Pull in non-free firmware blobs required by detected hardware:
    #   - Intel Wi-Fi 6E AX211      (iwlwifi)
    #   - Intel Bluetooth           (intel-bluetooth)
    #   - Killer E2600 / Intel IGC  (ethernet firmware)
    #   - Intel ME / SMBus / GNA    (platform firmware)
    enableRedistributableFirmware = true;

    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
          FastConnectable = true;
          # Required to pair PS4/PS5 (DualShock/DualSense) controllers and many
          # BT keyboards on BlueZ.
          ClassicBondedOnly = false;
        };
        Policy.AutoEnable = true;
      };
    };

    # Logitech LIGHTSPEED Receiver — exposes solaar for battery, DPI, button remap.
    logitech.wireless = {
      enable = true;
      enableGraphical = true;
    };

    # Steam udev rules — required for Steam Controller / Steam Deck dock /
    # DualSense Edge / VR HMDs to be recognised at all. DualShock works
    # without these via the kernel hid-sony driver.
    steam-hardware.enable = true;
  };

  # Compressed-RAM swap (64 GB box).
  #
  # Algorithm: lz4 — 3× the throughput (7,943 vs 2,612 MiB/s) and 3× lower
  # latency (1,708 vs 5,714 ns) than zstd, at the cost of ~28% less compression
  # (2.63× vs 3.37×). On 64 GB, the extra compression is worthless — the system
  # rarely fills even 16 GB of swap. lz4's lower CPU cost matters more for
  # gaming under memory pressure (benchmarks: xeome.dev/notes/Zram).
  #
  # Size: 25% of 64 GB = 16 GB zram. At lz4's 2.63× ratio that's ~42 GB
  # effective. Arch Wiki + systemd-zram-generator default to 50% but cap at
  # 4–8 GB; Fedora caps at 8 GB. 32 GB (50%) on a 64 GB box wastes metadata
  # memory for capacity that will never be touched. 16 GB is generous headroom.
  #
  # The 8 GB on-disk swapfile (hosts/predator/default.nix) is the overflow
  # safety net — zram's priority (default 100) ensures it's always preferred.
  zramSwap = {
    enable = true;
    algorithm = "lz4";
    memoryPercent = 25;
  };

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

  users.users.stoleyy = {
    isNormalUser = true;
    description = "stoleyy";
    shell = pkgs.fish;
    # On Wayland + systemd-logind, per-seat ACLs grant active sessions
    # /dev/input/event* access automatically — no "input" group needed.
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "plugdev"
      "gamemode"
    ];
    packages = with pkgs; [ kdePackages.kate ];
  };

  environment.shells = with pkgs; [
    fish
    bash
  ];
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    chipsec
  ];

  system.stateVersion = "25.11";
}
