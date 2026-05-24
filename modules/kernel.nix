{ pkgs, config, ... }:

{
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

    # chipsec.ko — userspace CLI added to environment.systemPackages in base.nix.
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
}
