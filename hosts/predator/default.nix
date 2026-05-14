{ pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
    editor = false;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # 8 GB swapfile — install script places root on Samsung 980 Pro
  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];

  networking.hostName = "predator";

  # sops-nix: decrypt secrets at activation using the host SSH Ed25519 key.
  # Setup steps (run once before declaring any sops.secrets):
  #   1. nix-shell -p ssh-to-age --run "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"
  #   2. paste the age pubkey into ../../.sops.yaml
  #   3. nix-shell -p sops --run "sops ../../secrets/secrets.yaml"
  #   4. declare each key under `secrets.<name> = { owner = ...; mode = ...; };`
  #
  # ProtonVPN — kernel WireGuard via modules/protonvpn.nix. Server is NL#448
  # (Amsterdam, Wg-nl1, NAT-PMP on so port-forwarding works for downstream
  # services that need it). Tunnel comes up at boot via systemd; kill switch
  # is active by default. See docs/protonvpn-wg-setup.md for setup steps.
  # Private key lives at /var/lib/protonvpn/privkey (root:root, mode 0400);
  # not in sops yet — Tier 2.1 in the optimization roadmap.
  modules.protonvpn = {
    enable = true;
    serverPublicKey = "yDABIIjKHTfyA+J+cuHetkq2G6u+9yiRh3OsEEPS01M=";
    serverEndpoint = "103.69.224.6:51820";
    # clientAddress defaults to 10.2.0.2/32 (matches Proton's issued tunnel IP)
    # killSwitch defaults to true
  };

  # sops-nix: decrypt secrets at activation using the host SSH Ed25519 key.
  # Currently unused (placeholder yaml). When you populate it (see comment
  # above sops block below), the natural first migration is moving the
  # ProtonVPN private key into sops — modules.protonvpn.privateKeyFile then
  # points at config.sops.secrets.protonvpn_wg_key.path.
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    validateSopsFiles = false; # placeholder yaml is plaintext until step 3 above
  };

  # Old prose note (kept for context, now stale): the previous setup used
  # protonvpn-gui (modules/apps.nix) with credentials in SecretService.
  # We've migrated to wg-quick above; the GUI stays installed as a fallback
  # for ad-hoc server picking, but the main tunnel is kernel-managed.

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
