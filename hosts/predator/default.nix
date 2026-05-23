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
    # games mount needs stoleyy:users so game-install (running as stoleyy via
    # qBittorrent) can create per-game subdirectories. The old comment said
    # "root:root is correct — the filesystem sets permissions" but that is wrong:
    # systemd-tmpfiles enforces these on every activation, overriding the filesystem
    # root inode. The previous failure was "Failed to resolve group 'stoleyy'" —
    # 'stoleyy' is a user, not a group. 'users' (GID 100) is the correct primary
    # group for a NixOS isNormalUser account.
    "d /home/stoleyy/games 0755 stoleyy users -"
    # /data is a general-purpose partition not directly written by user services;
    # root:root is correct there.
    "d /data               0755 root root -"
  ];

  specialisation = {
    # On-demand Plasma boot — boots to the SDDM greeter (no autologin) so
    # the session can be chosen from the dropdown. When the user returns to
    # Plasma as their daily driver, flip defaultSession in modules/desktop.nix
    # and remove this specialisation.
    plasma.configuration = {
      services.displayManager.defaultSession = lib.mkForce "plasma";
      services.displayManager.autoLogin.enable = lib.mkForce false;
    };

    # Verbose boot + tracing tools for diagnosing kernel/driver issues.
    # Select "debug" from the systemd-boot menu.
    # nomodeset disables KMS/DRM so Stage 1 errors print to the plain VGA
    # console instead of being swallowed by the NVIDIA framebuffer.
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

    # Pure gaming boot — autologins into Steam Gaming Mode via gamescope.
    # Used exclusively for fullscreen gaming; boots straight to the Steam
    # library with no desktop, compositor, or security-monitoring overhead.
    # Session name "steam" is registered by programs.steam.gamescopeSession
    # (modules/gaming.nix) and confirmed present in the SDDM SessionDir.
    gaming-tuned.configuration = {
      # Boot into Steam Gaming Mode via gamescope-session.
      services.displayManager.defaultSession = lib.mkForce "steam";
      services.displayManager.autoLogin = {
        enable = lib.mkForce true;
        user = lib.mkForce "stoleyy";
      };

      # Gamescope display config: 4K @ 240 Hz OLED + VRR on HDMI-A-1.
      #
      # Initial revision passed --width/--height (internal nested-compositor
      # resolution only) without --output-width/--output-height (KMS output
      # mode), no --prefer-output, and --hdr-enabled. The result was a black
      # screen with a flashing TTY cursor: gamescope took over KMS, failed
      # to drive a usable mode on the OLED, exited, and SDDM gave up — the
      # exact failure mode the original comment warned about for HDR.
      #
      # HDR is intentionally OFF here. Re-enable in a separate commit once a
      # picture is confirmed, so HDR remains a clean git bisect point.
      # --prefer-output HDMI-A-1 mirrors home/stoleyy/hyprland.nix and makes
      # connector selection deterministic. --output-width/-height set the
      # actual KMS mode (the older --width/--height only sized the internal
      # compositor, leaving the output at the EDID-preferred mode).
      # WLR_NO_HARDWARE_CURSORS=1 and WLR_RENDERER=vulkan are the standard
      # NVIDIA + wlroots session workarounds. ENABLE_GAMESCOPE_WSI=1 is
      # required for NVIDIA Vulkan WSI. DXVK_ASYNC=1 enables async shader
      # compilation.
      programs.steam.gamescopeSession = {
        args = [
          "--output-width"
          "3840"
          "--output-height"
          "2160"
          "--refresh"
          "240"
          "--prefer-output"
          "HDMI-A-1"
          "--adaptive-sync"
        ];
        env = {
          ENABLE_GAMESCOPE_WSI = "1";
          DXVK_ASYNC = "1";
          WLR_RENDERER = "vulkan";
          WLR_NO_HARDWARE_CURSORS = "1";
        };
      };

      # Disable PPD — pulled in by plasma6, conflicts with the explicit
      # governor service below. Without this, both fight over sysfs writes.
      services.power-profiles-daemon.enable = lib.mkForce false;

      # Pin governor to performance for the entire gaming session.
      powerManagement.cpuFreqGovernor = lib.mkForce "performance";

      # Override EPP from base.nix's balance_performance to performance.
      # performance EPP + performance governor = maximum sustained boost.
      systemd.services.cpu-power-tuning.script = lib.mkForce ''
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          echo performance > "$f" || true
        done
        echo 1 > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost || true
      '';

      # Shed security monitoring overhead. This boot entry is exclusively
      # used for fullscreen gaming — no network-facing interactive services.
      security.auditd.enable = lib.mkForce false;
      security.audit.enable = lib.mkForce false;
      security.apparmor.enable = lib.mkForce false;

      # Performance kernel params. Appended to the base list; Linux
      # last-param-wins means init_on_alloc=0 overrides hardening.nix's =1.
      boot.kernelParams = [
        "mitigations=off"
        "nowatchdog"
        # Remove page-zeroing overhead. ~1-7% CPU savings in
        # allocation-heavy games. Last-param-wins overrides hardening.nix.
        "init_on_alloc=0"
        "init_on_free=0"
        # Reduce timer interrupt lock contention across cores.
        "skew_tick=1"
        # Eliminate PCIe ASPM link transition latency.
        # Increases idle power draw — acceptable for a dedicated gaming boot.
        "pcie_aspm=off"
        # Make hard IRQs preemptible — lowers worst-case interrupt latency.
        "threadirqs"
      ];
    };
  };
}
