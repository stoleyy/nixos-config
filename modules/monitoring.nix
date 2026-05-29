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
    enable = false;
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
    };
  };

  # Only create the vector log dir when vector is enabled; avoids creating
  # an orphaned dir owned by the vector user when the service is disabled.
  systemd.tmpfiles.rules = lib.optionals config.services.vector.enable [
    "d /var/log/vector 0750 vector vector -"
  ];
}
