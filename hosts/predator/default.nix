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
  #   4. declare each key under `secrets.<name> = { owner = ...; mode = ...; };`
  #
  # Proton VPN is intentionally NOT a sops secret here: we run the official
  # `protonvpn-gui` client (modules/apps.nix) and it stores credentials in the
  # SecretService keyring at sign-in time, so there is nothing for sops to do.
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    validateSopsFiles = false;   # placeholder yaml is plaintext until step 3 above
  };

  # Wazuh HIDS agent — disabled until the Wazuh manager exists on the
  # OPNsense side and sops-nix has been bootstrapped (see secrets/secrets.yaml).
  # To enable:
  #   1. Bootstrap sops-nix (see comments above).
  #   2. Add `wazuh-agent-registration-password: <pw>` to secrets.yaml.
  #   3. Uncomment the block below, set managerAddress to the manager's
  #      LAN FQDN or IP, then `nixos-rebuild switch`.
  #
  # sops.secrets.wazuh-agent-registration-password = {
  #   owner = "root";
  #   mode  = "0400";
  # };
  #
  # services.wazuh-agent = {
  #   enable                   = true;
  #   managerAddress           = "wazuh.lan";
  #   registrationPasswordFile = config.sops.secrets.wazuh-agent-registration-password.path;
  # };

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
