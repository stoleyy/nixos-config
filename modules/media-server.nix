{
  config,
  pkgs,
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
  users.groups.media = { };

  # ---------- Jellyfin (media streaming, port 8096) ----------
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
  # NVIDIA hardware transcoding needs render + video; media for shared dirs
  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    "media"
  ];

  # ---------- Sonarr (TV shows, port 8989) ----------
  services.sonarr = {
    enable = true;
    openFirewall = true;
  };
  users.users.sonarr.extraGroups = [ "media" ];

  # ---------- Radarr (movies, port 7878) ----------
  services.radarr = {
    enable = true;
    openFirewall = true;
  };
  users.users.radarr.extraGroups = [ "media" ];

  # ---------- Prowlarr (indexer proxy, port 9696) ----------
  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };

  # ---------- qBittorrent (torrent client, WebUI 6881, BT 50000) ----------
  services.qbittorrent = {
    enable = true;
    openFirewall = true;
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
  users.users.qbittorrent.extraGroups = [ "media" ];

  # qBittorrent: upstream already has full hardening; we override the three
  # settings that differ: ProtectHome off (media in /home), ProtectSystem
  # strict (upstream uses full), PrivateTmp on (upstream disables it).
  systemd.services.qbittorrent = {
    wants = [ "wg-quick-protonvpn.service" ];
    after = [ "wg-quick-protonvpn.service" ];
    serviceConfig = {
      ProtectHome = lib.mkForce false;
      ProtectSystem = lib.mkForce "strict";
      ReadWritePaths = [
        "/var/lib/qbittorrent"
        "/home/stoleyy/games/media"
      ];
      PrivateTmp = lib.mkForce true;
    };
  };

  # ---------- systemd service hardening ----------
  # Jellyfin: upstream has most hardening; add ProtectSystem=strict + ProtectClock
  systemd.services.jellyfin.serviceConfig = {
    ProtectSystem = "strict";
    ReadWritePaths = [
      "/var/lib/jellyfin"
      "/home/stoleyy/games/media"
    ];
    ProtectClock = true;
  };
  systemd.services.sonarr.serviceConfig = {
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
  };
  systemd.services.radarr.serviceConfig = {
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
  };
  systemd.services.prowlarr.serviceConfig = {
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
  };
  systemd.services.bazarr.serviceConfig = {
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
  };

  # Torrenting port needs UDP too (openFirewall only opens TCP)
  networking.firewall.allowedUDPPorts = [ 50000 ];

  # ---------- Bazarr (subtitles, port 6767) ----------
  services.bazarr = {
    enable = true;
    openFirewall = true;
  };
  users.users.bazarr.extraGroups = [ "media" ];

  # ---------- media directory tree ----------
  systemd.tmpfiles.rules = [
    "d /home/stoleyy/games/media                       0775 stoleyy media -"
    "d /home/stoleyy/games/media/movies                0775 stoleyy media -"
    "d /home/stoleyy/games/media/tv                    0775 stoleyy media -"
    "d /home/stoleyy/games/media/downloads             0775 stoleyy media -"
    "d /home/stoleyy/games/media/downloads/complete    0775 stoleyy media -"
    "d /home/stoleyy/games/media/downloads/incomplete  0775 stoleyy media -"
  ];

  # stoleyy needs media group for direct file access
  users.users.stoleyy.extraGroups = [ "media" ];

  # ---------- on-demand startup ----------
  # Don't start any media service at boot; use `sudo systemctl start media-stack.target`
  systemd.services.jellyfin.wantedBy = lib.mkForce [ ];
  systemd.services.sonarr.wantedBy = lib.mkForce [ ];
  systemd.services.radarr.wantedBy = lib.mkForce [ ];
  systemd.services.prowlarr.wantedBy = lib.mkForce [ ];
  systemd.services.qbittorrent.wantedBy = lib.mkForce [ ];
  systemd.services.bazarr.wantedBy = lib.mkForce [ ];

  systemd.targets.media-stack = {
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
}
