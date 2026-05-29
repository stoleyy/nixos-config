{
  config,
  pkgs,
  lib,
  host,
  ...
}:

{
  imports = [ ./hardware-configuration.nix ];

  # ── Build-time assertions — catch real pitfalls at eval, not at boot ──
  assertions = [
    {
      # LOAD-BEARING: Intel VMD must be force-loaded in initrd for root NVMe
      # discovery on this board. Moving it to availableKernelModules or removing
      # it = unbootable system (PR #8 bricked, #14 fixed). See CLAUDE.md.
      assertion = builtins.elem "vmd" config.boot.initrd.kernelModules;
      message = "CRITICAL: 'vmd' missing from boot.initrd.kernelModules — system will not boot (NVMe root unreachable)";
    }
    {
      # ProtonVPN kill-switch relies on nftables. If someone switches to iptables,
      # the killswitch rules silently don't apply.
      assertion = config.networking.nftables.enable;
      message = "nftables must be enabled — ProtonVPN kill-switch and media-server firewall rules require it";
    }
    {
      # RTX 4070 (Ada) crash-loops Plasma Wayland and SDDM Wayland greeter with
      # the open kernel module (driver 580.x). See modules/nvidia.nix:26-31.
      assertion = !config.hardware.nvidia.open;
      message = "hardware.nvidia.open must be false — open kernel module crash-loops Plasma Wayland on this RTX 4070 (Ada)";
    }
    {
      # lanzaboote and systemd-boot both write to the ESP; if both are enabled,
      # they fight and one silently wins, usually producing an unsignable boot
      # chain that bricks on next reboot. Use `lib.mkForce false` on
      # systemd-boot.enable when enabling lanzaboote. `or false` keeps this
      # assertion safe when the lanzaboote module isn't imported.
      assertion = !(config.boot.loader.systemd-boot.enable && (config.boot.lanzaboote.enable or false));
      message = "lanzaboote and systemd-boot cannot both be enabled — set systemd-boot.enable = lib.mkForce false";
    }
  ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      # Bumped from 10 → 20 after a lanzaboote/nh-clean interaction left the
      # box unbootable: nh removed kernels that older UKIs still referenced
      # by hash, and the menu didn't have enough fallback generations to pick
      # a working one. More retention = more rescue options without rescue USB.
      configurationLimit = 20;
      editor = false;
      # bootCounting — available in nixpkgs master but not 25.11 stable.
      # Re-enable after upgrading to 25.17+:
      # bootCounting = { enable = true; trials = 2; };
    };
    # 3 s gives just enough window to hit Space/arrow and pick a previous
    # generation when the default entry is broken. The autologin chain hides
    # this from normal use, so the UX cost is invisible.
    timeout = 3;
    efi.canTouchEfiVariables = true;
  };

  # 8 GB swapfile — install script places root on Samsung 980 Pro
  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];

  # Intentional host data mounts live HERE, not in hardware-configuration.nix.
  # Both are LUKS-encrypted (opened in initrd via hardware-configuration.nix)
  # and referenced by their /dev/mapper names. nofail + device-timeout so a
  # LUKS failure degrades to a boot warning instead of a hard stop.
  fileSystems."${host.gamesDir}" = {
    device = "/dev/mapper/cryptgames";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  # /data — LUKS-encrypted general-purpose partition (backups, media, archives).
  fileSystems."${host.dataDir}" = {
    device = "/dev/mapper/cryptdata";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  networking.hostName = "predator";

  # OpenRGB — RGB controller for this Intel-platform host.
  # Server binds to 0.0.0.0:6742 (no --server-host flag exists).
  # Blocked from LAN access via networking.nix firewall (port not opened).
  services.hardware.openrgb = {
    enable = true;
    motherboard = "intel";
  };

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
    # Restart WireGuard when the secret rotates so the new key takes effect immediately.
    restartUnits = [ "wg-quick-protonvpn.service" ];
  };
  # TODO: add github-pat to secrets.yaml before re-enabling —   sops.secrets.github-pat = {
  # TODO: add github-pat to secrets.yaml before re-enabling —     owner = "stoleyy";
  # TODO: add github-pat to secrets.yaml before re-enabling —     mode = "0400";
  # TODO: add github-pat to secrets.yaml before re-enabling —   };
  modules.protonvpn = {
    enable = true;
    privateKeyFile = config.sops.secrets.protonvpn-private-key.path;
    serverPublicKey = "Rtsl6k9WA9t04Vt+EDUD3TlSr9+YL6YcTFwiSB1qBwA=";
    serverEndpoint = "146.70.84.2:51820";
    # clientAddress defaults to 10.2.0.2/32 (matches Proton's issued tunnel IP)
    # killSwitch defaults to true
    autoRotate = {
      enable = true;
      interval = "15min"; # quality check interval (only swaps on degradation)
      hysteresisMs = 20; # only swap if new server is 20ms+ faster
      refreshPool = {
        enable = true;
        country = "US";
        top = 0; # all servers in the closest cities
        refreshInterval = "3h";
        # Southern Ohio — geo-filter to 5 nearest cities
        lat = 39.3;
        lon = -83.5;
        geoCities = 5;
      };
    };
  };

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
    "d ${host.gamesDir} 0755 ${host.user} users -"
    # /data is a general-purpose partition not directly written by user services;
    # root:root is correct there.
    "d ${host.dataDir}  0755 root root -"
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

    # Console-like gaming boot — launches gamescope directly via greetd,
    # a minimal session launcher. No login screen, no greeter, no display
    # manager UI. greetd creates a PAM + logind session and runs gamescope,
    # like a game console powering on. If gamescope exits or crashes,
    # greetd restarts it automatically.
    gaming-tuned.configuration = {
      services = {
        # Disable SDDM — greetd replaces it for this boot entry.
        displayManager.sddm.enable = lib.mkForce false;

        # greetd: minimal session launcher with PAM + logind integration.
        greetd = {
          enable = true;
          restart = true;
          settings.default_session = {
            command =
              let
                gamescopeSession = pkgs.callPackage ../../packages/gamescope-session.nix { inherit host; };
              in
              "${gamescopeSession}";
            inherit (host) user;
          };
        };

        # Disable PPD — pulled in by plasma6, conflicts with the explicit
        # governor service below. Without this, both fight over sysfs writes.
        power-profiles-daemon.enable = lib.mkForce false;

        # Shed the network monitoring / obfuscation daemons for the
        # pure-gaming session (same rationale as the auditd/apparmor
        # disables below — this entry runs nothing network-facing).
        suricata.enable = lib.mkForce false;
        crowdsec.enable = lib.mkForce false;
        vector.enable = lib.mkForce false;
        tor.enable = lib.mkForce false;
      };

      # Force xdg-desktop-portal OFF for the greetd/gamescope session.
      #
      # Chicken-and-egg: Steam's CEF requests org.freedesktop.portal.Desktop
      # during startup, the portal tries to activate its backends (gtk + kde),
      # both backends abort because there is no display yet (gamescope hasn't
      # opened one — that requires Steam to launch first), portal hangs 120 s,
      # Steam gives up, gamescope's primary child dies, session ends at TTY.
      #
      # With portal disabled, Steam's StartServiceByName fails immediately
      # (NameHasNoOwner instead of NoReply timeout) and Steam falls back to
      # non-portal code paths. Big Picture loses screencast/file-picker portal
      # integration, but those are non-essential for gaming.
      xdg.portal.enable = lib.mkForce false;

      # Gamescope display config: 4K @ 240 Hz OLED + VRR.
      #
      # --backend drm is REQUIRED — the NixOS module does not add it.
      # Without it gamescope cannot find a display when launched as a
      # standalone session (exits code 1 instantly).
      #
      # --prefer-output pins the connector (host.monitor = DP-2).
      # --prefer-vk-device selects the RTX 4070 (10de:2786) for Vulkan
      # compositing, skipping the simpledrm device.
      #
      # HDR: disabled. NVIDIA DRM driver 580.x does not expose HDR
      # metadata properties through atomic modesetting on this connector.
      # gamescope --hdr-enabled crashes immediately during DRM init.
      # Re-enable after NVIDIA ships DRM HDR support (driver 570+ had
      # partial; watch for full atomic HDR in 585+/open-gpu-kernel-modules).
      #
      # --adaptive-sync: VRR / G-Sync Compatible works natively on DP.
      # gamescope DRM backend may or may not honour it — left enabled;
      # if it causes issues remove it (session will still boot).
      programs.steam.gamescopeSession = {
        args = [
          "--backend"
          "drm"
          "--prefer-output"
          host.monitor
          "--prefer-vk-device"
          "10de:2786"
          "--output-width"
          "3840"
          "--output-height"
          "2160"
          "--nested-refresh"
          "240"
          "--adaptive-sync"
        ];
        env = {
          ENABLE_GAMESCOPE_WSI = "1";
          DXVK_ASYNC = "1";
          # Force logind seat backend. gamescope's libseat fallback
          # chain (seatd → logind → builtin) can fail to acquire DRM
          # master during session handoff. logind is the correct
          # backend when systemd-logind manages the session.
          LIBSEAT_BACKEND = "logind";
          # GLVND EGL vendor ICD discovery. Without this, libglvnd's
          # EGL dispatcher can't find libEGL_nvidia.so.0 (or mesa),
          # so Xwayland's libepoxy aborts with "No provider of
          # eglGetCurrentContext found". Normal desktop sessions get
          # this from the display manager; greetd doesn't set it.
          __EGL_VENDOR_LIBRARY_DIRS = "/run/opengl-driver/share/glvnd/egl_vendor.d";
          # Disable glamor (GPU-accelerated 2D) inside gamescope's Xwayland.
          # Same libepoxy 1.5.10 + NVIDIA 580.x crash as the Hyprland session
          # (modules/hyprland.nix wraps the system Xwayland with -glamor off,
          # but gamescope spawns its own from its closure). XWAYLAND_NO_GLAMOR
          # is the env-var equivalent. 3D/Vulkan games are unaffected.
          XWAYLAND_NO_GLAMOR = "1";
        };
      };

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
      security = {
        auditd.enable = lib.mkForce false;
        audit.enable = lib.mkForce false;
        apparmor.enable = lib.mkForce false;
      };

      # Media-stack services already use wantedBy=mkForce[] (on-demand only).
      # Disabling them via enable=mkForce false would break user/group
      # declarations in media-server.nix. They won't run unless manually started.

      # Start GPU at full clocks — entire session is gaming
      systemd.services.nvidia-undervolt.serviceConfig.ExecStart = lib.mkForce (
        pkgs.writeShellScript "nvidia-undervolt-gaming" ''
          /run/current-system/sw/bin/nvidia-smi -rgc 2>/dev/null || true
          /run/current-system/sw/bin/nvidia-smi -pl 200 2>/dev/null || true
          sleep infinity
        ''
      );

      # Auto-clean old gamescope session logs
      systemd.tmpfiles.rules = [
        "e /home/stoleyy/gamescope-session.log - - - 7d -"
      ];

      # Performance kernel params. Appended to the base list; Linux
      # last-param-wins means init_on_alloc=0 overrides hardening.nix's =1.
      #
      # REMOVED (evidence-based audit):
      # - mitigations=off: Zero benefit on Raptor Lake — Phoronix tested 198
      #   benchmarks on i9-13900K, geometric mean unchanged. Hardware mitigates
      #   in silicon. High security cost for no gain.
      # - pcie_aspm=off: 16-64µs L1 exit latency is irrelevant at 240Hz
      #   (4.17ms frames). PCIe stays in L0 during sustained gaming. Wastes
      #   20-30W idle power for zero measurable benefit.
      boot.kernelParams = [
        "nowatchdog"
        # Remove page-zeroing overhead. ~1-7% CPU savings in
        # allocation-heavy games. Last-param-wins overrides hardening.nix.
        "init_on_alloc=0"
        "init_on_free=0"
        # skew_tick: marginal on 24-thread CPU (microsecond jitter reduction)
        # but not harmful. threadirqs: pairs with preempt=full for lower
        # worst-case IRQ latency. Both are low-impact but theoretically sound.
        "skew_tick=1"
        "threadirqs"
      ];
    };
  };
}
