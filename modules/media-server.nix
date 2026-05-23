{
  lib,
  ...
}:

# Core media server stack: Jellyfin + *arr suite + qBittorrent + Bazarr.
#
# All services run as dedicated system users sharing a common `media` group
# for filesystem access to /home/stoleyy/games/media/. qBittorrent is bound
# to the ProtonVPN WireGuard tunnel so torrent traffic is VPN-only (the
# kill switch in modules/protonvpn.nix is the second layer).
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
      stoleyy.extraGroups = [ "media" ];
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
            SavePath = "/home/stoleyy/games/media/downloads/complete";
            TempPath = "/home/stoleyy/games/media/downloads/incomplete";
            TempPathEnabled = true;
          };
          # Bind to VPN interface — no traffic exits without the tunnel
          Connection = {
            InterfaceName = "protonvpn";
            InterfaceAddress = "10.2.0.2";
          };
        };
        BitTorrent.Session = {
          Interface = "protonvpn";
          InterfaceAddress = "10.2.0.2";
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
      # qBittorrent: upstream already has full hardening; we override the three
      # settings that differ: ProtectHome off (media in /home), ProtectSystem
      # strict (upstream uses full), PrivateTmp on (upstream disables it).
      # bindsTo: if VPN dies, qBittorrent stops too — prevents IP leaks.
      qbittorrent = {
        bindsTo = [ "wg-quick-protonvpn.service" ];
        after = [ "wg-quick-protonvpn.service" ];
        wantedBy = lib.mkForce [ ];
        serviceConfig = {
          ProtectHome = lib.mkForce false;
          ProtectSystem = lib.mkForce "strict";
          ReadWritePaths = [
            "/var/lib/qbittorrent"
            "/home/stoleyy/games/media"
          ];
          PrivateTmp = lib.mkForce true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
            "AF_NETLINK"
          ];
          CapabilityBoundingSet = "";
          SystemCallFilter = [ "@system-service" ];
          SystemCallArchitectures = "native";
          MemoryDenyWriteExecute = true;
        };
      };

      # Jellyfin: upstream has most hardening; add the full sandboxing stack.
      # PrivateDevices omitted — Jellyfin needs /dev/dri for NVENC GPU transcoding.
      jellyfin = {
        wantedBy = lib.mkForce [ ];
        serviceConfig = {
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/jellyfin"
            "/home/stoleyy/games/media"
          ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
            "AF_NETLINK"
          ];
          CapabilityBoundingSet = "";
          SystemCallFilter = [ "@system-service" ];
          SystemCallArchitectures = "native";
          # MemoryDenyWriteExecute omitted: .NET CoreCLR JIT requires W+X pages
        };
      };

      sonarr = {
        wantedBy = lib.mkForce [ ];
        serviceConfig = {
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/sonarr"
            "/home/stoleyy/games/media"
          ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          CapabilityBoundingSet = "";
          SystemCallFilter = [ "@system-service" ];
          SystemCallArchitectures = "native";
          # MemoryDenyWriteExecute omitted: .NET/Mono JIT requires W+X pages
        };
      };

      radarr = {
        wantedBy = lib.mkForce [ ];
        serviceConfig = {
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/radarr"
            "/home/stoleyy/games/media"
          ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          CapabilityBoundingSet = "";
          SystemCallFilter = [ "@system-service" ];
          SystemCallArchitectures = "native";
          # MemoryDenyWriteExecute omitted: .NET/Mono JIT requires W+X pages
        };
      };

      prowlarr = {
        wantedBy = lib.mkForce [ ];
        serviceConfig = {
          ProtectSystem = "strict";
          ReadWritePaths = [ "/var/lib/prowlarr" ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          CapabilityBoundingSet = "";
          SystemCallFilter = [ "@system-service" ];
          SystemCallArchitectures = "native";
          # MemoryDenyWriteExecute omitted: .NET/Mono JIT requires W+X pages
        };
      };

      bazarr = {
        wantedBy = lib.mkForce [ ];
        serviceConfig = {
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/bazarr"
            "/home/stoleyy/games/media"
          ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          CapabilityBoundingSet = "";
          SystemCallFilter = [ "@system-service" ];
          SystemCallArchitectures = "native";
          MemoryDenyWriteExecute = true;
        };
      };
    };

    # ---------- media directory tree ----------
    tmpfiles.rules = [
      "d /home/stoleyy/games/media                       0775 stoleyy media -"
      "d /home/stoleyy/games/media/movies                0775 stoleyy media -"
      "d /home/stoleyy/games/media/tv                    0775 stoleyy media -"
      "d /home/stoleyy/games/media/downloads             0775 stoleyy media -"
      "d /home/stoleyy/games/media/downloads/complete    0775 stoleyy media -"
      "d /home/stoleyy/games/media/downloads/incomplete  0775 stoleyy media -"
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
}
