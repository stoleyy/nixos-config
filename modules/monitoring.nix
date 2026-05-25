# Self-monitoring: ntfy notifications on failure, beszel metrics hub, gatus service probes, vector log pipeline.
{ pkgs, lib, ... }:

let
  # Services that should notify on failure. Each gets unitConfig.OnFailure
  # pointing to the ntfy notification template below.
  monitoredServices = [
    "wg-quick-protonvpn"
    "protonvpn-rotate"
    "protonvpn-pool-refresh"
    "jellyfin"
    "sonarr"
    "radarr"
    "prowlarr"
    "qbittorrent"
    "bazarr"
    "ollama"
    "nvidia-tdp"
    "nvidia-persistenced"
    "lact"
    "scx"
  ];

  monitorOverrides = builtins.listToAttrs (
    map (
      name: lib.nameValuePair name { unitConfig.OnFailure = [ "ntfy-failure@%n.service" ]; }
    ) monitoredServices
  );
in
{
  # ── ntfy-sh: local push notification server ──
  # Receives failure alerts from systemd units via the template below.
  # Web UI at http://localhost:2586, subscribe to "alerts" topic.
  # Mobile: install ntfy app, point at http://<LAN-IP>:2586, subscribe to "alerts".
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = ":2586";
      base-url = "http://localhost:2586";
    };
  };

  # ── OnFailure notification template + monitored service overrides ──
  # ntfy-failure@<unit>.service is instantiated by systemd when a monitored
  # unit fails. %i expands to the failed unit name.
  systemd.services = monitorOverrides // {
    "ntfy-failure@" = {
      description = "Notify on failure of %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -s -d 'Unit %i failed on predator' -H 'Title: Service Failure' -H 'Priority: high' -H 'Tags: rotating_light' http://localhost:2586/alerts";
      };
    };
  };

  # ── Beszel: lightweight monitoring hub + agent ──
  # Single-host setup: hub serves the dashboard, agent reports metrics.
  # Dashboard at http://localhost:8090 (first visit creates admin account).
  #
  # First-time setup:
  #   1. Visit http://localhost:8090, create admin account
  #   2. Add a system → hub generates a KEY
  #   3. Write KEY=<value> to /etc/beszel-agent.env
  #   4. sudo systemctl restart beszel-agent
  services.beszel = {
    hub = {
      enable = true;
      port = 8090;
    };
    agent = {
      enable = true;
      smartmon.enable = true;
      # KEY comes from the hub after adding a system. Agent won't start
      # until this file exists and contains KEY=<ssh-ed25519 ...>.
      environmentFile = "/etc/beszel-agent.env";
    };
  };

  # ── Gatus: declarative service health probes ──
  # Status page at http://localhost:8080.
  services.gatus = {
    enable = true;
    settings = {
      web.port = 8080;
      endpoints = [
        {
          name = "Jellyfin";
          url = "http://localhost:8096";
          interval = "5m";
          conditions = [ "[STATUS] == any(200, 302)" ];
        }
        {
          name = "Sonarr";
          url = "http://localhost:8989";
          interval = "5m";
          conditions = [ "[STATUS] == any(200, 302)" ];
        }
        {
          name = "Radarr";
          url = "http://localhost:7878";
          interval = "5m";
          conditions = [ "[STATUS] == any(200, 302)" ];
        }
        {
          name = "Prowlarr";
          url = "http://localhost:9696";
          interval = "5m";
          conditions = [ "[STATUS] == any(200, 302)" ];
        }
        {
          name = "qBittorrent";
          url = "http://localhost:6881";
          interval = "5m";
          conditions = [ "[STATUS] == any(200, 302)" ];
        }
        {
          name = "Bazarr";
          url = "http://localhost:6767";
          interval = "5m";
          conditions = [ "[STATUS] == any(200, 302)" ];
        }
        {
          name = "Ollama";
          url = "http://localhost:11434";
          interval = "5m";
          conditions = [ "[STATUS] == 200" ];
        }
        {
          name = "DNS (Quad9)";
          url = "9.9.9.9";
          dns = {
            query-name = "cloudflare.com";
            query-type = "A";
          };
          interval = "2m";
          conditions = [ "[DNS_RCODE] == NOERROR" ];
        }
      ];
      alerting.ntfy = {
        url = "http://localhost:2586";
        topic = "alerts";
        default-alert = {
          enabled = true;
          failure-threshold = 3;
          success-threshold = 2;
          send-on-resolved = true;
        };
      };
    };
  };

  # ── Vector: structured log pipeline ──
  # Tails systemd journal, enriches with unit metadata, writes to
  # /var/log/vector/ as structured JSON. Validated at build time.
  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      sources.journal = {
        type = "journald";
        current_boot_only = true;
      };
      transforms.filter_important = {
        type = "filter";
        inputs = [ "journal" ];
        condition = ''
          .PRIORITY != null && to_int!(.PRIORITY) <= 4
        '';
      };
      sinks.local_json = {
        type = "file";
        inputs = [ "filter_important" ];
        path = "/var/log/vector/journal-%Y-%m-%d.json";
        encoding.codec = "json";
        framing.method = "newline_delimited";
      };
    };
  };

  # Ensure vector log directory exists.
  systemd.tmpfiles.rules = [
    "d /var/log/vector 0750 vector vector -"
  ];
}
