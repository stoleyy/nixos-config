{ pkgs, lib, ... }:

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
  # Setup steps (run once before declaring any sops.secrets):
  #   1. nix-shell -p ssh-to-age --run "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"
  #   2. paste the age pubkey into ../../.sops.yaml
  #   3. nix-shell -p sops --run "sops ../../secrets/secrets.yaml"
  #   4. add protonvpn_wg_key + uncomment the secrets.* block below
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    validateSopsFiles = false;   # placeholder yaml is plaintext until step 3 above

    # Uncomment once secrets.yaml has been populated (step 4 above):
    # secrets.protonvpn_wg_key = {
    #   owner = "root";
    #   mode  = "0400";
    # };
  };

  specialisation = {
    # Boot with Hyprland as the default session instead of Plasma.
    # Select "hyprland" from the systemd-boot menu.
    hyprland.configuration = {
      services.displayManager.defaultSession = lib.mkForce "hyprland";
    };

    # Verbose boot + tracing tools for diagnosing kernel/driver issues.
    # Select "debug" from the systemd-boot menu.
    # nomodeset disables KMS/DRM so Stage 1 errors print to the plain VGA console
    # instead of being swallowed by the NVIDIA framebuffer.
    debug.configuration = {
      boot.kernelParams = [
        "loglevel=7"
        "debug"
        "nomodeset"
      ];
      environment.systemPackages = with pkgs; [
        strace
        ltrace
        gdb
      ];
    };
  };
}
