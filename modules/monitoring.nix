# Self-monitoring: ntfy notifications on failure, beszel metrics hub, gatus service probes, vector log pipeline.
# Live: ntfy-sh, vector (journal + Suricata→ntfy), beszel (hub+agent), and the
# host-IDS alerts (kernel-module loads + user-space persistence drift). Gatus
# stays off until there's a remote sink/dashboard worth probing.
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
  # ── ntfy-sh: local alert server (heatmap W4: detection without alerting) ──
  # Bound to LOOPBACK only (127.0.0.1) — never LAN-exposed, no openFirewall —
  # so enabling it does not widen the inbound surface. Alerts land at the local
  # web UI (http://localhost:2586) and are pushed by the OnFailure hooks below.
  # For phone delivery, either open 2586 on a trusted LAN or front it with a
  # reverse proxy — deliberately NOT done here (would re-open an inbound port).
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = "127.0.0.1:2586";
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

  # Wire OnFailure → the local alert for the connectivity- and
  # security-critical units (heatmap W4). These are dotted attribute paths, so
  # they MERGE into the existing units rather than redefining them; every unit
  # named here already exists in this config (protonvpn, dnscrypt, suricata,
  # crowdsec are all enabled), so nothing creates an empty stub. %n expands to
  # the failing unit's name → ntfy-failure@<unit>.service.
  systemd.services."wg-quick-protonvpn".unitConfig.OnFailure = "ntfy-failure@%n.service";
  systemd.services."dnscrypt-proxy".unitConfig.OnFailure = "ntfy-failure@%n.service";
  systemd.services."suricata".unitConfig.OnFailure = "ntfy-failure@%n.service";
  systemd.services."crowdsec".unitConfig.OnFailure = "ntfy-failure@%n.service";

  # ── Host-IDS alerts (no-Wazuh interim) ───────────────────────────────────
  # The Wazuh manager is disabled (lib/default.nix), so auditd's host telemetry
  # (modules/auditd.nix) is collected but never analyzed or alerted. These two
  # units turn the two highest-signal, low-noise slices into ntfy alerts without
  # Wazuh:
  #   1. kernel module loads — classic LKM-rootkit / driver-implant signal
  #   2. user-space persistence drift — on immutable NixOS the read-only store
  #      rules out system-binary tampering, so a botnet must persist in $HOME

  # 1) Tail the audit log for POST-BOOT kernel module load/unload events
  #    (auditd tags init_module/finit_module/delete_module with key="modules").
  systemd.services.audit-module-alert = {
    description = "Alert on kernel module load/unload (auditd key=modules) → ntfy";
    after = [
      "auditd.service"
      "ntfy-sh.service"
    ];
    wants = [ "auditd.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.OnFailure = "ntfy-failure@%n.service";
    serviceConfig = {
      Restart = "always";
      RestartSec = "10s";
      # -n0 → only events after this unit starts, so the hundreds of boot-time
      # module loads don't alert; post-boot loads are rare and worth a look.
      ExecStart = pkgs.writeShellScript "audit-module-alert" ''
        set -uo pipefail
        ${pkgs.coreutils}/bin/tail -F -n0 /var/log/audit/audit.log 2>/dev/null | while IFS= read -r line; do
          case "$line" in
            *'key="modules"'*)
              who=$(printf '%s' "$line" | ${pkgs.gnugrep}/bin/grep -oE 'comm="[^"]*"' | ${pkgs.coreutils}/bin/head -n1)
              ${pkgs.curl}/bin/curl -fsS \
                -H 'Title: Kernel module event' -H 'Priority: high' -H 'Tags: warning' \
                -d "auditd modules ($who): $line" "${ntfyUrl}/alerts" >/dev/null || true
              ;;
          esac
        done
      '';
    };
  };

  # 2) Snapshot the user-space persistence surface periodically; ntfy on drift.
  systemd.services.persist-watch = {
    description = "User-space persistence integrity check → ntfy";
    after = [ "ntfy-sh.service" ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "persist-watch";
      ExecStart = pkgs.writeShellScript "persist-watch" ''
        set -uo pipefail
        home=/home/stoleyy
        base=/var/lib/persist-watch/baseline
        cur=$(${pkgs.coreutils}/bin/mktemp)

        # Persistence surface a botnet must use on immutable NixOS: XDG autostart,
        # user systemd units, ~/.local/bin (PATH hijack), and shell rc files
        # (sha256sum follows the HM symlinks, so a swapped target is detected).
        for d in "$home/.config/autostart" "$home/.config/systemd/user" "$home/.local/bin"; do
          [ -d "$d" ] && ${pkgs.findutils}/bin/find "$d" -type f -exec ${pkgs.coreutils}/bin/sha256sum {} +
        done >> "$cur" 2>/dev/null || true
        for f in "$home/.bashrc" "$home/.zshrc" "$home/.zshenv" "$home/.zprofile" "$home/.profile"; do
          [ -e "$f" ] && ${pkgs.coreutils}/bin/sha256sum "$f" >> "$cur" 2>/dev/null || true
        done
        ${pkgs.coreutils}/bin/sort -o "$cur" "$cur"

        if [ ! -f "$base" ]; then
          ${pkgs.coreutils}/bin/cp "$cur" "$base" # establish baseline silently
          ${pkgs.coreutils}/bin/rm -f "$cur"
          exit 0
        fi
        if ! ${pkgs.diffutils}/bin/diff -q "$base" "$cur" >/dev/null 2>&1; then
          delta=$(${pkgs.diffutils}/bin/diff "$base" "$cur" | ${pkgs.coreutils}/bin/head -n 20)
          ${pkgs.curl}/bin/curl -fsS \
            -H 'Title: User-space persistence changed' -H 'Priority: high' -H 'Tags: warning' \
            -d "persist-watch drift: $delta" "${ntfyUrl}/alerts" >/dev/null || true
          ${pkgs.coreutils}/bin/cp "$cur" "$base" # re-baseline → alert once per change
        fi
        ${pkgs.coreutils}/bin/rm -f "$cur"
      '';
    };
  };
  systemd.timers.persist-watch = {
    description = "Run the user-space persistence check periodically";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "15m";
      Persistent = true;
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
      enable = true;
      port = 8090;
    };
    agent = {
      enable = true;
      smartmon.enable = true;
      environmentFile = "/etc/beszel-agent.env";
    };
  };

  # Placeholder so beszel-agent has an EnvironmentFile before the one-time hub
  # KEY is written (steps above). `f` creates it empty only if absent — it never
  # clobbers the KEY you add later. Resource spikes (a miner pegging the RTX
  # 4070, or a DDoS saturating uplink) are the clearest no-signature botnet tell.
  systemd.tmpfiles.rules = [ "f /etc/beszel-agent.env 0600 root root - " ];

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
