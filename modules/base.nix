{ pkgs, config, ... }:

{
  nix.settings = {
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
    experimental-features = [ "nix-command" "flakes" ];
    max-jobs = "auto";
    cores    = 0;
    # Perf tuning: dedup the /nix/store + keep build outputs for faster incremental rebuilds.
    auto-optimise-store = true;
    keep-outputs        = true;
    keep-derivations    = true;
  };

  nix.optimise = {
    automatic = true;
    dates     = [ "03:45" ];
  };

  # Nix builds run at idle CPU scheduling — `nh os switch` doesn't block gaming/work.
  nix.daemonCPUSchedPolicy = "idle";

  programs.nix-ld.enable = true;

  programs.nh = {
    enable          = true;
    flake           = "/etc/nixos";
    clean.enable    = true;
    clean.extraArgs = "--keep-since 7d --keep 5";
  };

  programs.direnv = {
    enable            = true;
    nix-direnv.enable = true;
  };

  programs.fish.enable  = true;
  programs.dconf.enable = true;

  # F-21: replace deprecated glibc nscd with memory-safe Rust nsncd
  services.nscd = {
    enable      = true;
    enableNsncd = true;
  };

  time.timeZone      = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS        = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT    = "en_US.UTF-8";
    LC_MONETARY       = "en_US.UTF-8";
    LC_NAME           = "en_US.UTF-8";
    LC_NUMERIC        = "en_US.UTF-8";
    LC_PAPER          = "en_US.UTF-8";
    LC_TELEPHONE      = "en_US.UTF-8";
    LC_TIME           = "en_US.UTF-8";
  };

  console.keyMap = "us";

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
  boot.kernelPackages = pkgs.linuxPackages;

  # chipsec.ko — userspace CLI added to environment.systemPackages below.
  # `sudo chipsec_util spi dump` / `sudo chipsec_main` for platform security
  # and firmware diagnostics. Module is built against the running kernel.
  boot.extraModulePackages = [ config.boot.kernelPackages.chipsec ];

  # Stop Linux throttling Proton games that trip split-lock atomics.
  # Merges with the NVIDIA DRM params declared in modules/nvidia.nix.
  # transparent_hugepage=madvise: kernel default is "always" which
  # background-promotes 2 MB pages and can cause latency spikes during
  # heavy NVMe writes (Nix builds, shader compiles). madvise gives the
  # same JVM/database benefits without surprise stalls.
  boot.kernelParams = [
    "split_lock_detect=off"
    "transparent_hugepage=madvise"
  ];

  # === CPU (i7-13700K) ===
  # Raptor Lake degradation patches + perf microcode.
  hardware.cpu.intel.updateMicrocode = true;
  # P-cores locked at boost; lower wake-to-clock latency. Desktop = no power concern.
  powerManagement.cpuFreqGovernor = "performance";

  # === Memory (64 GB) ===
  # /tmp in RAM — default 50% cap (~32 GB) on this box. Massive speedup for
  # nix builds, archive extraction, compilations. Replaces cleanOnBoot (tmpfs
  # is wiped on every boot inherently).
  boot.tmp.useTmpfs = true;

  boot.kernel.sysctl = {
    "vm.swappiness"                   = 10;    # 64 GB — barely swap
    "vm.vfs_cache_pressure"           = 50;    # Keep dentry/inode cache around longer
    "net.core.default_qdisc"          = "fq";  # Pair with BBR
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_fastopen"           = 3;     # TFO saves an RTT per TCP connection
  };

  # === Storage (NVMe) ===
  services.fstrim.enable = true;

  # Geolocation daemon — Plasma 6 NightLight `mode = "automatic"` (set in
  # home/stoleyy/plasma.nix) silently no-ops without geoclue's systemd unit;
  # KWin otherwise gets `geoclue.service not found` over DBus.
  services.geoclue2.enable = true;

  # Local command-not-found via nix-index-database (HM module added in
  # lib/default.nix). Disables the deprecated nixpkgs CSV lookup.
  programs.command-not-found.enable = false;

  # Pull in non-free firmware blobs required by detected hardware:
  #   - Intel Wi-Fi 6E AX211      (iwlwifi)
  #   - Intel Bluetooth           (intel-bluetooth)
  #   - Killer E2600 / Intel IGC  (ethernet firmware)
  #   - Intel ME / SMBus / GNA    (platform firmware)
  hardware.enableRedistributableFirmware = true;

  hardware.bluetooth = {
    enable      = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental    = true;
        FastConnectable = true;
        # Required to pair PS4/PS5 (DualShock/DualSense) controllers and many
        # BT keyboards on BlueZ.
        ClassicBondedOnly = false;
      };
      Policy.AutoEnable = true;
    };
  };

  # Logitech LIGHTSPEED Receiver — exposes solaar for battery, DPI, button remap.
  hardware.logitech.wireless = {
    enable          = true;
    enableGraphical = true;
  };

  # Steam udev rules — required for Steam Controller / Steam Deck dock /
  # DualSense Edge / VR HMDs to be recognised at all. DualShock works
  # without these via the kernel hid-sony driver.
  hardware.steam-hardware.enable = true;

  # Firmware updates via LVFS.
  services.fwupd.enable = true;

  # Compressed-RAM swap. Free responsiveness win; complements the on-disk swapfile.
  zramSwap.enable = true;

  # systemd-oomd watches cgroup memory pressure (PSI) and kills the worst
  # offender before the kernel OOM killer freezes the desktop for 10+ s.
  # 64 GB usually doesn't OOM, but Brave-with-200-tabs + Steam + a leaking
  # game can; this is the safety net. 20s pressure duration avoids transient
  # spikes triggering a kill.
  systemd.oomd = {
    enable             = true;
    enableRootSlice    = true;
    enableUserSlices   = true;
    enableSystemSlice  = true;
    settings.OOM.DefaultMemoryPressureDurationSec = "20s";
  };

  users.users.stoleyy = {
    isNormalUser = true;
    description  = "stoleyy";
    shell        = pkgs.fish;
    # On Wayland + systemd-logind, per-seat ACLs grant active sessions
    # /dev/input/event* access automatically — no "input" group needed.
    extraGroups  = [ "networkmanager" "wheel" "video" "plugdev" "gamemode" ];
    packages     = with pkgs; [ kdePackages.kate ];
  };

  environment.shells          = with pkgs; [ fish bash ];
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages  = with pkgs; [ git vim wget chipsec ];

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1week
    Storage=persistent
    ForwardToSyslog=no
  '';

  # Pre-empt the rare "Too many open files" crash in Steam/Wine prefixes on
  # big games + mod managers. Default ceiling is 1024 (soft) / 524288 (hard);
  # bumping the soft limit to ~1M avoids hitting it.
  systemd.settings.Manager.DefaultLimitNOFILE = "1048576";

  systemd.coredump.enable = false;
  system.stateVersion     = "25.11";
}
