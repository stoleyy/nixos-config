{ config, pkgs, ... }:

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
  };

  nix.optimise = {
    automatic = true;
    dates     = [ "03:45" ];
  };

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
      };
      Policy.AutoEnable = true;
    };
  };

  # Logitech LIGHTSPEED Receiver — exposes solaar for battery, DPI, button remap.
  hardware.logitech.wireless = {
    enable          = true;
    enableGraphical = true;
  };

  # Firmware updates via LVFS.
  services.fwupd.enable = true;

  # Compressed-RAM swap. Free responsiveness win; complements the on-disk swapfile.
  zramSwap.enable = true;

  # Wipe /tmp between boots.
  boot.tmp.cleanOnBoot = true;

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
  environment.systemPackages  = with pkgs; [ git vim wget ];

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1week
    Storage=persistent
    ForwardToSyslog=no
  '';

  systemd.coredump.enable = false;
  system.stateVersion     = "25.11";
}
