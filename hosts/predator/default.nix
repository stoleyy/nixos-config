{ pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 20;
      editor = false;
    };
    efi.canTouchEfiVariables = true;
  };

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
  # ProtonVPN — kernel WireGuard via modules/protonvpn.nix. Server is US-OH#24
  # (Columbus, OH; predator-dedicated config so it doesn't collide with the
  # Jellyfin indexer-pool's WG sessions, since Proton caps concurrent WG to
  # 10 per account). NAT-PMP on, NetShield on (server-side blocklist; doesn't
  # conflict with OISD on OPNsense — they layer additively when WG is up).
  # Tunnel comes up at boot via systemd; kill switch active by default.
  # See docs/protonvpn-wg-setup.md.
  #
  # Private key lives at /var/lib/protonvpn/privkey (root:root, mode 0400);
  # not in sops yet — Tier 2.1 in the optimization roadmap.
  modules.protonvpn = {
    enable = true;
    serverPublicKey = "Rtsl6k9WA9t04Vt+EDUD3TlSr9+YL6YcTFwiSB1qBwA=";
    serverEndpoint = "146.70.84.2:51820";
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
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
    validateSopsFiles = false; # placeholder yaml is plaintext until step 3 above
  };

  # Wazuh HIDS agent — disabled until the Wazuh manager exists on the
  # OPNsense side and sops-nix has been bootstrapped (see secrets/secrets.yaml).
  # The overlay (overlays/wazuh-agent.nix) still carries lib.fakeHash; run the
  # nix-prefetch-github one-liner in that file and substitute the real source
  # hash before first enable.
  # To enable:
  #   1. Bootstrap sops-nix (see comments above).
  #   2. Add `wazuh-agent-registration-password: <pw>` to secrets.yaml.
  #   3. Uncomment the block below, set managerAddress to the manager's
  #      LAN FQDN or IP, then `nixos-rebuild switch`.
  #
  # sops.secrets.wazuh-agent-registration-password = {
  #   owner = "root";
  #   mode = "0400";
  # };
  #
  # services.wazuh-agent = {
  #   enable = true;
  #   managerAddress = "wazuh.lan";
  #   registrationPasswordFile = config.sops.secrets.wazuh-agent-registration-password.path;
  # };

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

    # Opt-in maximum-performance boot. Select "gaming-tuned" from the
    # systemd-boot menu for dedicated gaming sessions; the DEFAULT boot stays
    # secure (mitigations on — this box runs Wazuh/auditd/hardening). Trades
    # Spectre-class mitigations for the last ~5-15% CPU-bound headroom in
    # Proton/DXVK. kernelParams append to the parent's (preempt=full is
    # already inherited from base); the governor needs mkForce to override
    # base.nix's powersave.
    gaming-tuned.configuration = {
      boot.kernelParams = [
        "mitigations=off"
        "nowatchdog"
      ];
      powerManagement.cpuFreqGovernor = lib.mkForce "performance";
    };
  };
}
