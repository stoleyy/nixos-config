# Media server stack: Jellyfin, Sonarr/Radarr/Prowlarr, qBittorrent (VPN-bound), Bazarr — depends on protonvpn.nix.
{
  config,
  lib,
  host,
  ...
}:

# Core media server stack: Jellyfin + *arr suite + qBittorrent + Bazarr.
#
# All services run as dedicated system users sharing a common `media` group
# for filesystem access to the media directory. qBittorrent is bound to the
# ProtonVPN WireGuard tunnel so torrent traffic is VPN-only (the kill switch
# in modules/protonvpn.nix is the second layer).
#
# Coupling: qBittorrent binds to the "protonvpn" WireGuard interface
# (defined in modules/protonvpn.nix → networking.wg-quick.interfaces.protonvpn).
# The VPN client address is derived from config.modules.protonvpn.clientAddress.
#
# First-boot setup (after `nixos-rebuild switch`):
#   1. Jellyfin:     http://localhost:8096  — wizard, add libraries, enable NVENC
#   2. Prowlarr:     http://localhost:9696  — add indexers
#   3. Sonarr:       http://localhost:8989  — root folder, connect Prowlarr + qBit
#   4. Radarr:       http://localhost:7878  — same as Sonarr
#   5. qBittorrent:  http://localhost:6881  — change default password
#   6. Bazarr:       http://localhost:6767  — connect to Sonarr + Radarr
#
# Secrets: API keys are auto-generated on first startup by each service.
# Inter-service wiring is done through each service's WebUI.
# Migrate to sops-nix once the age key is bootstrapped.

let
  # VPN address without CIDR suffix — derived from the protonvpn module option.
  vpnAddr = builtins.head (lib.splitString "/" config.modules.protonvpn.clientAddress);

  # Common systemd hardening options shared by all media services.
  hardeningDefaults = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectSystem = "strict";
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RestrictNamespaces = true;
    LockPersonality = true;
    CapabilityBoundingSet = "";
    SystemCallFilter = [ "@system-service" ];
    SystemCallArchitectures = "native";
    MemoryDenyWriteExecute = true;
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
  };

  # Factory for the 4 standard *arr services — on-demand, sandboxed, media-accessible.
  # qBittorrent and Jellyfin are too different (VPN binding, GPU access) for a factory.
  mkArrService =
    {
      stateDir,
      mediaPaths ? [ host.mediaDir ],
      relaxJit ? false,
    }:
    {
      wantedBy = lib.mkForce [ ];
      serviceConfig =
        hardeningDefaults
        // {
          ReadWritePaths = [ stateDir ] ++ mediaPaths;
        }
        // lib.optionalAttrs relaxJit {
          MemoryDenyWriteExecute = lib.mkForce false;
        };
    };
in
{
  # ---------- shared media group ----------
  users = {
    groups.media = { };
    users = {
      # NVIDIA hardware transcoding needs render + video; media for shared dirs
      jellyfin.extraGroups = [
        "render"
        "video"
        "media"
      ];
      sonarr.extraGroups = [ "media" ];
      radarr.extraGroups = [ "media" ];
      qbittorrent.extraGroups = [ "media" ];
      bazarr.extraGroups = [ "media" ];
      # stoleyy needs media group for direct file access
      ${host.user}.extraGroups = [ "media" ];
    };
  };

  services = {
    # ---------- Jellyfin (media streaming, port 8096) ----------
    jellyfin = {
      enable = true;
      openFirewall = false;
    };

    # ---------- Sonarr (TV shows, port 8989) ----------
    sonarr = {
      enable = true;
      openFirewall = false;
    };

    # ---------- Radarr (movies, port 7878) ----------
    radarr = {
      enable = true;
      openFirewall = false;
    };

    # ---------- Prowlarr (indexer proxy, port 9696) ----------
    prowlarr = {
      enable = true;
      openFirewall = false;
    };

    # ---------- qBittorrent (torrent client, WebUI 6881, BT 50000) ----------
    qbittorrent = {
      enable = true;
      openFirewall = false;
      webuiPort = 6881;
      torrentingPort = 50000;
      serverConfig = {
        LegalNotice.Accepted = true;
        Preferences = {
          General.Locale = "en";
          Downloads = {
            SavePath = "${host.mediaDir}/downloads/complete";
            TempPath = "${host.mediaDir}/downloads/incomplete";
            TempPathEnabled = true;
          };
          # Bind to VPN interface — no traffic exits without the tunnel.
          # Interface name matches networking.wg-quick.interfaces key in protonvpn.nix.
          Connection = {
            InterfaceName = "protonvpn";
            InterfaceAddress = vpnAddr;
          };
          # WebUI binds to loopback only (qbit-automation audit). The WebUI
          # exposes the "run external program on completion" setting — an RCE
          # primitive — so it must never be LAN-reachable; this is
          # defense-in-depth atop the closed firewall. HostHeaderValidation
          # blocks DNS-rebind / CSRF from a browser pointed at localhost:6881.
          WebUI = {
            Address = "127.0.0.1";
            HostHeaderValidation = true;
          };
        };
        BitTorrent.Session = {
          Interface = "protonvpn";
          InterfaceAddress = vpnAddr;
          InterfaceName = "protonvpn";
          # Disable DHT/PeX/LSD — these leak the real IP outside the tunnel
          DHT = false;
          PeX = false;
          LSD = false;
        };
      };
    };

    # ---------- Bazarr (subtitles, port 6767) ----------
    bazarr = {
      enable = true;
      openFirewall = false;
    };
  };

  # ---------- systemd service hardening + on-demand startup ----------
  systemd = {
    services = {
      # qBittorrent: explicit (VPN binding + custom hardening overrides).
      # bindsTo: if VPN dies, qBittorrent stops too — prevents IP leaks.
      # Service name matches protonvpn.nix → networking.wg-quick.interfaces.protonvpn.
      qbittorrent = {
        bindsTo = [ "wg-quick-protonvpn.service" ];
        after = [ "wg-quick-protonvpn.service" ];
        wantedBy = lib.mkForce [ ];
        serviceConfig = hardeningDefaults // {
          ProtectHome = lib.mkForce false;
          ProtectSystem = lib.mkForce "strict";
          PrivateTmp = lib.mkForce true;
          ReadWritePaths = [
            "/var/lib/qbittorrent"
            host.mediaDir
          ];
          # qBittorrent needs AF_NETLINK for network interface binding (VPN).
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
            "AF_NETLINK"
          ];
        };
      };

      # Jellyfin: explicit (GPU transcoding + .NET JIT).
      # PrivateDevices off — needs /dev/dri for NVENC.
      # MemoryDenyWriteExecute off — .NET CoreCLR JIT requires W+X pages.
      jellyfin = {
        wantedBy = lib.mkForce [ ];
        serviceConfig = hardeningDefaults // {
          PrivateDevices = lib.mkForce false;
          MemoryDenyWriteExecute = lib.mkForce false;
          ReadWritePaths = [
            "/var/lib/jellyfin"
            host.mediaDir
          ];
          # Jellyfin needs AF_NETLINK for network interface enumeration.
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
            "AF_NETLINK"
          ];
        };
      };

      # *arr suite — standard on-demand services via factory.
      # .NET/Mono JIT needs MemoryDenyWriteExecute relaxed (relaxJit).
      sonarr = mkArrService {
        stateDir = "/var/lib/sonarr";
        relaxJit = true;
      };
      radarr = mkArrService {
        stateDir = "/var/lib/radarr";
        relaxJit = true;
      };
      prowlarr = mkArrService {
        stateDir = "/var/lib/prowlarr";
        relaxJit = true;
        mediaPaths = [ ];
      };
      bazarr = mkArrService { stateDir = "/var/lib/bazarr"; };
    };

    # ---------- media directory tree ----------
    tmpfiles.rules = [
      "d ${host.mediaDir}                       0775 ${host.user} media -"
      "d ${host.mediaDir}/movies                0775 ${host.user} media -"
      "d ${host.mediaDir}/tv                    0775 ${host.user} media -"
      "d ${host.mediaDir}/downloads             0775 ${host.user} media -"
      "d ${host.mediaDir}/downloads/complete    0775 ${host.user} media -"
      "d ${host.mediaDir}/downloads/incomplete  0775 ${host.user} media -"
    ];

    # ---------- on-demand startup ----------
    # Don't start any media service at boot; use `sudo systemctl start media-stack.target`
    targets.media-stack = {
      description = "Media Server Stack (Jellyfin + arr + qBittorrent)";
      wants = [
        "network-online.target"
        "jellyfin.service"
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
        "qbittorrent.service"
        "bazarr.service"
      ];
      after = [
        "network-online.target"
      ];
    };
  };

  # Torrenting port (TCP+UDP) — needed for incoming peer connections.
  # qBittorrent is interface-bound to protonvpn, so this only matters on the tunnel.
  networking.firewall = {
    allowedTCPPorts = [ 50000 ];
    allowedUDPPorts = [ 50000 ];
  };

  assertions = [
    {
      assertion = config.modules.protonvpn.enable;
      message = "modules.media-server requires modules.protonvpn.enable = true (VPN bind address needed for qBittorrent and arr services)";
    }
  ];
}
