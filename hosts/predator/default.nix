{ pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot = {
    enable             = true;
    configurationLimit = 20;
    editor             = false;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # 8 GB swapfile — install script places root on Samsung 980 Pro
  swapDevices = [ { device = "/swapfile"; size = 8192; } ];

  networking.hostName = "predator";

  # sops-nix: decrypt secrets at activation using the host SSH Ed25519 key.
  # Run `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub` to get the age pubkey
  # for .sops.yaml, then `sops secrets/secrets.yaml` to create/edit secrets.
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;

    secrets.protonvpn_wg_key = {
      owner = "root";
      mode  = "0400";
    };
  };

  specialisation = {
    # Boot with Hyprland as the default session instead of Plasma.
    # Select "hyprland" from the systemd-boot menu.
    hyprland.configuration = {
      services.displayManager.defaultSession = "hyprland";
    };

    # Verbose boot + tracing tools for diagnosing kernel/driver issues.
    # Select "debug" from the systemd-boot menu.
    debug.configuration = {
      boot.kernelParams = [
        "loglevel=7"
        "debug"
      ];
      environment.systemPackages = with pkgs; [
        strace
        ltrace
        gdb
      ];
    };
  };
}
