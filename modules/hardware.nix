_:

{
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
}
