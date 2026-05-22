{
  config,
  pkgs,
  lib,
  ...
}:

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

  # Intentional host data mounts live HERE, not appended to the generated
  # hardware-configuration.nix — nixos-generate-config clobbers hand-added
  # fileSystems entries (see CLAUDE.md Pitfalls). Both are keyed by UUID; the
  # physical device node is deliberately NOT asserted — repo history
  # contradicted itself (nvme0n1p2 vs nvme1n1p2 across files/commits). If a
  # node is ever needed, confirm on the box with `blkid`, never from here.
  #
  # /home/stoleyy/games — Steam/Lutris library (former NTFS games partition,
  # reformatted ext4). Pre-#37 it was never flake-declared, so every real
  # `nixos-rebuild switch` dropped it: switch-to-configuration stopped the old
  # generation's mount unit and the new generation declared none (observed
  # 2026-05-16, breaking Steam/Lutris). nofail + device-timeout so a
  # missing/slow disk degrades to a boot warning instead of a hard
  # "Dependency failed for /home/stoleyy/games" stop.
  fileSystems."/home/stoleyy/games" = {
    device = "/dev/disk/by-uuid/efd6d32e-54f9-4e6d-965f-67279a31da47";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  # /data — former Windows NVMe, wiped + reformatted ext4. by-UUID sidesteps
  # the by-label ambiguity that kept this out of the flake in #37 (two ext4
  # partitions briefly shared label "data"); the UUID is unambiguous. Same
  # nofail + device-timeout degradation contract as games above.
  # Former Windows NVMe (nvme1n1) — wiped and repartitioned as a single ext4.
  # General-purpose data partition (backups, media, project archives).
  fileSystems."/data" = {
    device = "/dev/disk/by-uuid/88c50d98-1905-405d-a9c2-5ce522c9ad77";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

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
  # Private key managed by sops-nix (encrypted in secrets/secrets.yaml).
  sops.secrets.protonvpn-private-key = {
    owner = "root";
    mode = "0400";
  };
  modules.protonvpn = {
    enable = true;
    privateKeyFile = config.sops.secrets.protonvpn-private-key.path;
    serverPublicKey = "Rtsl6k9WA9t04Vt+EDUD3TlSr9+YL6YcTFwiSB1qBwA=";
    serverEndpoint = "146.70.84.2:51820";
    # clientAddress defaults to 10.2.0.2/32 (matches Proton's issued tunnel IP)
    # killSwitch defaults to true
    autoRotate = {
      enable = true;
      interval = "30min";
      hysteresisMs = 15; # only swap if new server is 15ms+ faster
      refreshPool = {
        enable = true;
        country = "US";
        top = 10;
        refreshInterval = "6h";
      };
    };
  };

  # sops-nix: decrypt secrets at activation using the host SSH Ed25519 key.
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
    validateSopsFiles = true;
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

  # Ensure mount-point directories exist with correct ownership before systemd
  # mounts the filesystems declared in hardware-configuration.nix.
  systemd.tmpfiles.rules = [
    # Mount-point directories: root:root is correct — these are just mount targets,
    # the mounted filesystem sets the actual permissions. Using stoleyy:stoleyy here
    # caused early-boot "Failed to resolve group 'stoleyy'" errors because the user
    # database may not be fully available when 00-nixos.conf tmpfiles rules run.
    "d /home/stoleyy/games 0755 root root -"
    "d /data               0755 root root -"
  ];

  specialisation = {
    # Boot with Hyprland as the default session instead of Plasma.
    # Select "hyprland" from the systemd-boot menu.
    hyprland.configuration = {
      services.displayManager = {
        defaultSession = lib.mkForce "hyprland";
        autoLogin = {
          enable = true;
          user = "stoleyy";
        };
      };
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
    # already inherited from base). power-profiles-daemon (Plasma 6) manages
    # the governor; mkForce pins it to performance for this boot entry.
    gaming-tuned.configuration = {
      boot.kernelParams = [
        "mitigations=off"
        "nowatchdog"
        # Remove page-zeroing overhead — init_on_free is the costly half
        # (doubles zeroing work). ~1-7% CPU savings in allocation-heavy games.
        "init_on_alloc=0"
        "init_on_free=0"
        # Reduce timer interrupt lock contention across cores.
        "skew_tick=1"
        # workqueue.power_efficient=0 is now in the default boot (base.nix)
        # Eliminate PCIe Active State Power Management link transition latency.
        # Increases idle power draw — acceptable for a dedicated gaming boot.
        "pcie_aspm=off"
        # Make hard IRQs preemptible — lowers worst-case interrupt latency.
        "threadirqs"
      ];
      powerManagement.cpuFreqGovernor = lib.mkForce "performance";
    };
  };
}
