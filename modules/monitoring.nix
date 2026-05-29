# Self-monitoring: ntfy notifications on failure, beszel metrics hub, gatus service probes, vector log pipeline.
# All services currently disabled — flip enables back when a remote sink or dashboard is set up.
{
  pkgs,
  lib,
  config,
  ...
}:

let
  ntfyUrl = "http://localhost:2586";

  # Gatus endpoint factory — eliminates the 6 near-identical HTTP blocks.
  mkHttpEndpoint =
    { name, port }:
    {
      inherit name;
      url = "http://localhost:${toString port}";
      interval = "5m";
      conditions = [ "[STATUS] == any(200, 302)" ];
    };
in
{
  # ── ntfy-sh: local push notification server ──
  # Web UI at http://localhost:2586, subscribe to "alerts" topic.
  # Mobile: install ntfy app, point at http://<LAN-IP>:2586, subscribe to "alerts".
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = ":2586";
      base-url = ntfyUrl;
    };
  };

  # ── OnFailure notification template ──
  # flip ntfy-sh enable above to activate; add OnFailure = "ntfy-failure@%n" to any service.
  systemd.services."ntfy-failure@" = {
    description = "Notify on failure of %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.curl}/bin/curl -s -d 'Unit %i failed on ${config.networking.hostName}' -H 'Title: Service Failure' -H 'Priority: high' -H 'Tags: rotating_light' ${ntfyUrl}/alerts";
    };
  };

  # ── Beszel: lightweight monitoring hub + agent ──
  # Dashboard at http://localhost:8090 (first visit creates admin account).
  #
  # First-time setup:
  #   1. Visit http://localhost:8090, create admin account
  #   2. Add a system → hub generates a KEY
  #   3. Write KEY=<value> to /etc/beszel-agent.env
  #   4. sudo systemctl restart beszel-agent
  services.beszel = {
    hub = {
      enable = false;
      port = 8090;
    };
    agent = {
      enable = false;
      smartmon.enable = true;
      environmentFile = "/etc/beszel-agent.env";
    };
  };

  # ── Gatus: declarative service health probes ──
  # Status page at http://localhost:8080.
  # Media services are on-demand (wantedBy=[]) — Gatus only probes always-on services.
  # OnFailure handles media service crash alerts instead.
  services.gatus = {
    enable = false;
    settings = {
      web.port = 8080;
      endpoints =
        map mkHttpEndpoint [
          {
            name = "Ollama";
            port = 11434;
          }
          {
            name = "Beszel Hub";
            port = 8090;
          }
          {
            name = "ntfy";
            port = 2586;
          }
        ]
        ++ [
          {
            name = "DNS";
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
        url = ntfyUrl;
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
  # Tails journald (priority ≤ 4) → structured JSON at /var/log/vector/.
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

      # ── Suricata EVE JSON alert pipeline ──────────────────────────────────
      # Tails /var/log/suricata/eve.json, filters for alerts, pushes to ntfy
      # and archives to /var/log/vector/ for audit.
      sources.suricata_eve = {
        type = "file";
        include = [ "/var/log/suricata/eve.json" ];
        read_from = "end";
      };

      # Each line from the file source lands in .message as a raw string.
      # Parse it to a structured event before filtering.
      transforms.suricata_parse = {
        type = "remap";
        inputs = [ "suricata_eve" ];
        source = ''
          . = parse_json!(.message)
        '';
      };

      transforms.suricata_alerts = {
        type = "filter";
        inputs = [ "suricata_parse" ];
        condition = ''
          .event_type == "alert"
        '';
      };

      # Format a human-readable one-liner for the ntfy notification body.
      transforms.suricata_ntfy_fmt = {
        type = "remap";
        inputs = [ "suricata_alerts" ];
        source = ''
          sig = string(.alert.signature) ?? "unknown"
          src = string(.src_ip) ?? "?"
          dst = string(.dest_ip) ?? "?"
          .message = sig + " | " + src + " → " + dst
        '';
      };

      # Push to ntfy — subscribe at ${ntfyUrl}/alerts
      # or on mobile: point ntfy app at http://<LAN-IP>:2586.
      sinks.ntfy_suricata = {
        type = "http";
        inputs = [ "suricata_ntfy_fmt" ];
        uri = "${ntfyUrl}/alerts";
        method = "post";
        encoding.codec = "text";
        request.headers = {
          Title = "Suricata IDS Alert";
          Priority = "high";
          Tags = "rotating_light";
        };
      };

      # Archive raw alert JSON for offline review / future Wazuh ingest.
      sinks.suricata_alerts_file = {
        type = "file";
        inputs = [ "suricata_alerts" ];
        path = "/var/log/vector/suricata-alerts-%Y-%m-%d.json";
        encoding.codec = "json";
        framing.method = "newline_delimited";
      };
    };
  };

  # Vector runs with DynamicUser=true — declare LogsDirectory so systemd
  # creates /var/log/vector/ with the ephemeral uid and adds it to
  # ReadWritePaths.  0755 lets stoleyy (waybar IDS script) enter the dir;
  # vector writes files 0644 so they are world-readable.
  # (systemd.tmpfiles.rules cannot resolve the ephemeral "vector" user.)
  systemd.services.vector.serviceConfig = lib.mkIf config.services.vector.enable {
    LogsDirectory = "vector";
    LogsDirectoryMode = "0755";
  };
}
