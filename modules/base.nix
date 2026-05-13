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
    enable       = true;
    flake        = "/etc/nixos";
    clean.enable = true;
    clean.extraArgs = "--keep-since 7d --keep 5";
  };

  programs.direnv = {
    enable         = true;
    nix-direnv.enable = true;
  };

  programs.fish.enable = true;

  # F-25: required for home-manager services.easyeffects to persist its dconf settings.
  # Without this, EasyEffects launches but won't remember preset/EQ state across reboots.
  programs.dconf.enable = true;

  # F-21: replace deprecated glibc nscd with memory-safe Rust nsncd
  services.nscd = {
    enable      = true;   # keep NSS cache for compat
    enableNsncd = true;   # use nsncd implementation, not glibc nscd
  };

  time.timeZone = "America/New_York";

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

  # Logitech LIGHTSPEED Receiver detected on Windows — exposes solaar for battery,
  # DPI, button remap. enableGraphical pulls in the Solaar Qt GUI.
  hardware.logitech.wireless = {
    enable          = true;
    enableGraphical = true;
  };

  # TPM 2.0 present on Acer Predator. Enables tpm2-tools userspace + pkcs11 provider
  # for future LUKS unlock, attestation, or fido2 via systemd-cryptenroll.
  security.tpm2 = {
    enable                 = true;
    pkcs11.enable          = true;
    tctiEnvironment.enable = true;
  };

  users.users.stoleyy = {
    isNormalUser = true;
    description  = "stoleyy";
    shell        = pkgs.fish;
    # Codex/F-29 note: "input" REMOVED from extraGroups.
    # On Wayland + systemd-logind (this stack), per-seat ACLs grant active sessions
    # /dev/input/event* access automatically — no group membership required.
    # If a specific device later needs raw access (custom HID, input-remapper, etc.),
    # add a targeted udev rule with TAG+="uaccess" instead of restoring group-wide access.
    extraGroups  = [
      "networkmanager"
      "wheel"
      "video"
      "plugdev"
      "gamemode"
    ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  environment.shells = with pkgs; [ fish bash ];

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1week
    Storage=persistent
    ForwardToSyslog=no
  '';

  systemd.coredump.enable = false;

  system.stateVersion = "25.11";
}
