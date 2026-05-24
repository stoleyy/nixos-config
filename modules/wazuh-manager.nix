# Wazuh manager + indexer + dashboard (single-node, podman) — disabled in lib/default.nix pending cert bootstrap.
{
  pkgs,
  config,
  lib,
  ...
}:

# Wazuh manager + indexer + dashboard, single-node, via podman/oci-containers.
#
# References:
#   - upstream Wazuh single-node docker-compose:
#     https://github.com/wazuh/wazuh-docker/tree/v4.13.1/single-node
#   - cert generation tool (run once manually before first start; see below):
#     https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html
#
# Topology (this box = predator, manager for the LAN-host OPNsense at 192.168.1.114):
#   - manager listens 1514/UDP (agent log channel), 1515/TCP (registration)
#   - indexer 9200/TCP (internal only, podman network)
#   - dashboard 443/TCP exposed on host LAN IP for the web UI
#
# Persistent state lives at /var/lib/wazuh-stack/{manager,indexer,dashboard,certs}.
# **Certs must exist before first boot** — see "First-time setup" at bottom of file.
#
# Memory budget for this stack (4.13.x):
#   - indexer JVM Xms=Xmx=2g (set explicitly here; default would balloon on a 64-GB box)
#   - manager + dashboard combined ~1.5 GB
#   - total: ~3.5 GB working set
#
# Predator has 64 GB RAM, so this is comfortably under budget.

let
  version = "4.13.1";

  # Bind-mount paths on the host
  stateDir = "/var/lib/wazuh-stack";
  managerDir = "${stateDir}/manager";
  indexerDir = "${stateDir}/indexer";
  dashDir = "${stateDir}/dashboard";
  certsDir = "${stateDir}/certs";
in
{
  # --- 0. Secrets (sops-nix) — passwords decrypted at activation, never in /nix/store.
  sops.secrets = {
    wazuh-indexer-password = {
      owner = "root";
      mode = "0400";
    };
    wazuh-api-password = {
      owner = "root";
      mode = "0400";
    };
    wazuh-dashboard-password = {
      owner = "root";
      mode = "0400";
    };
  };

  # --- 1. State directories + systemd services
  systemd = {
    # State directories owned by the container UIDs (Wazuh's images run as
    # root inside the container; bind-mount perms 0700 root:root). The
    # certs dir needs world-read for the dashboard to mount it as
    # a different image's UID — Wazuh's docs recommend chmod 750 on certs.
    tmpfiles.rules = [
      "d ${stateDir}   0750 root root - -"
      "d ${managerDir} 0750 root root - -"
      "d ${indexerDir} 0750 root root - -"
      "d ${dashDir}    0750 root root - -"
      "d ${certsDir}   0750 root root - -"
      "d ${stateDir}/agent-predator 0750 root root - -"
    ];

    services = {
      # --- 2. Podman network for inter-container service discovery by hostname.
      #     The oci-containers backend doesn't expose a clean "create network" hook,
      #     so we do it via a systemd one-shot before any container starts.
      podman-network-wazuh = {
        description = "Create podman network 'wazuh' for the manager stack";
        after = [ "podman.service" ];
        wants = [ "podman.service" ];
        before = [
          "podman-wazuh-manager.service"
          "podman-wazuh-indexer.service"
          "podman-wazuh-dashboard.service"
          "podman-wazuh-agent-predator.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.podman}/bin/podman network create --ignore wazuh";
          ExecStop = "${pkgs.podman}/bin/podman network rm --force wazuh";
        };
      };

      # --- 4. Inject sops-nix secrets into container environments at runtime.
      #     Podman's --env-file reads key=value lines from a file on the host.
      #     sops-nix decrypts to /run/secrets/<name> (root:root 0400) at activation.
      #     The systemd unit's ExecStartPre generates the env file from the secret.
      podman-wazuh-manager.serviceConfig.ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "inject-wazuh-manager-secrets" ''
          f=/run/wazuh-manager-env
          printf 'INDEXER_PASSWORD=%s\nAPI_PASSWORD=%s\n' \
            "$(cat ${config.sops.secrets.wazuh-indexer-password.path})" \
            "$(cat ${config.sops.secrets.wazuh-api-password.path})" > "$f"
          chmod 0400 "$f"
        '')
      ];
      podman-wazuh-dashboard.serviceConfig.ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "inject-wazuh-dashboard-secrets" ''
          f=/run/wazuh-dashboard-env
          printf 'DASHBOARD_PASSWORD=%s\nAPI_PASSWORD=%s\n' \
            "$(cat ${config.sops.secrets.wazuh-dashboard-password.path})" \
            "$(cat ${config.sops.secrets.wazuh-api-password.path})" > "$f"
          chmod 0400 "$f"
        '')
      ];
    };
  };

  # --- 3. The three containers + env file pass-through.
  virtualisation.oci-containers.containers = {

    wazuh-indexer = {
      image = "wazuh/wazuh-indexer:${version}";
      hostname = "wazuh-indexer";
      environment = {
        "OPENSEARCH_JAVA_OPTS" = "-Xms2g -Xmx2g"; # cap heap at 2 GB
        "node.name" = "wazuh-indexer";
        "cluster.name" = "wazuh-cluster";
        "discovery.type" = "single-node";
        "bootstrap.memory_lock" = "true";
      };
      ports = [ ]; # exposed only on the wazuh network, not host
      volumes = [
        "${indexerDir}:/var/lib/wazuh-indexer"
        "${certsDir}:/usr/share/wazuh-indexer/certs:ro"
      ];
      extraOptions = [
        "--network=wazuh"
        "--ulimit=memlock=-1:-1"
        "--ulimit=nofile=65536:65536"
      ];
    };

    wazuh-manager = {
      image = "wazuh/wazuh-manager:${version}";
      hostname = "wazuh-manager";
      dependsOn = [ "wazuh-indexer" ];
      environment = {
        "INDEXER_URL" = "https://wazuh-indexer:9200";
        "INDEXER_USERNAME" = "admin";
        # INDEXER_PASSWORD injected via sops-nix (see systemd override above)
        "FILEBEAT_SSL_VERIFICATION_MODE" = "full";
        "SSL_CERTIFICATE_AUTHORITIES" = "/etc/ssl/root-ca.pem";
        "SSL_CERTIFICATE" = "/etc/ssl/filebeat.pem";
        "SSL_KEY" = "/etc/ssl/filebeat.key";
        "API_USERNAME" = "wazuh-wui";
        # API_PASSWORD injected via sops-nix (see systemd override above)
      };
      ports = [
        "1514:1514/udp" # agent logs
        "1515:1515/tcp" # registration
        "55000:55000/tcp" # API
      ];
      volumes = [
        "${managerDir}/api/configuration:/var/ossec/api/configuration"
        "${managerDir}/etc:/var/ossec/etc"
        "${managerDir}/logs:/var/ossec/logs"
        "${managerDir}/queue:/var/ossec/queue"
        "${managerDir}/var-multigroups:/var/ossec/var/multigroups"
        "${managerDir}/integrations:/var/ossec/integrations"
        "${managerDir}/active-response/bin:/var/ossec/active-response/bin"
        "${managerDir}/agentless:/var/ossec/agentless"
        "${managerDir}/wodles:/var/ossec/wodles"
        "${managerDir}/filebeat-etc:/etc/filebeat"
        "${managerDir}/filebeat-var:/var/lib/filebeat"
        "${certsDir}/root-ca-manager.pem:/etc/ssl/root-ca.pem:ro"
        "${certsDir}/wazuh.manager.pem:/etc/ssl/filebeat.pem:ro"
        "${certsDir}/wazuh.manager-key.pem:/etc/ssl/filebeat.key:ro"
      ];
      extraOptions = [
        "--network=wazuh"
        "--env-file=/run/wazuh-manager-env"
      ];
    };

    # Predator's own Wazuh agent. Containerized for symmetry with the rest of
    # the stack — talks to wazuh-manager over the internal podman network so
    # there's no firewall traversal. Bind-mounts /var/log, /etc, /proc, /sys
    # read-only so the agent can read host audit/syslog state.
    wazuh-agent-predator = {
      image = "wazuh/wazuh-agent:${version}";
      hostname = "predator";
      dependsOn = [ "wazuh-manager" ];
      environment = {
        "WAZUH_MANAGER" = "wazuh-manager";
        "WAZUH_REGISTRATION_SERVER" = "wazuh-manager";
        "WAZUH_AGENT_GROUP" = "predator-workstations";
        "WAZUH_AGENT_NAME" = "predator";
      };
      volumes = [
        "/var/log:/host/var/log:ro"
        "/etc:/host/etc:ro"
        "/proc:/host/proc:ro"
        "/sys:/host/sys:ro"
        "/var/lib/wazuh-stack/agent-predator:/var/ossec/queue/agents"
      ];
      extraOptions = [
        "--network=wazuh"
        "--pid=host" # see host processes — auditd context
      ];
    };

    wazuh-dashboard = {
      image = "wazuh/wazuh-dashboard:${version}";
      hostname = "wazuh-dashboard";
      dependsOn = [
        "wazuh-indexer"
        "wazuh-manager"
      ];
      environment = {
        "OPENSEARCH_HOSTS" = ''["https://wazuh-indexer:9200"]'';
        "WAZUH_API_URL" = "https://wazuh-manager";
        "DASHBOARD_USERNAME" = "kibanaserver";
        # DASHBOARD_PASSWORD, API_PASSWORD injected via sops-nix (see systemd override above)
        "API_USERNAME" = "wazuh-wui";
      };
      ports = [
        "443:5601/tcp"
      ];
      volumes = [
        "${certsDir}/wazuh.dashboard.pem:/usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem:ro"
        "${certsDir}/wazuh.dashboard-key.pem:/usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem:ro"
        "${certsDir}/root-ca.pem:/usr/share/wazuh-dashboard/certs/root-ca.pem:ro"
        "${dashDir}/config:/usr/share/wazuh-dashboard/data/wazuh/config"
        "${dashDir}/custom:/usr/share/wazuh-dashboard/plugins/wazuh/public/assets/custom"
      ];
      extraOptions = [
        "--network=wazuh"
        "--env-file=/run/wazuh-dashboard-env"
      ];
    };

  };

  # --- 5. First-time setup notes (intentionally NOT automated — these are
  #     manual one-time steps; the alternative is a complex Nix-side cert
  #     pipeline that's worse than running a documented script once).
  #
  # Before first `nixos-rebuild switch` that activates these containers:
  #
  # A. Add secrets to sops (if not already present):
  #   nix-shell -p sops --run "sops secrets/secrets.yaml"
  #   # Add: wazuh-indexer-password, wazuh-api-password, wazuh-dashboard-password
  #
  # B. Generate certificates:
  #   sudo mkdir -p /var/lib/wazuh-stack/certs
  #   cd /var/lib/wazuh-stack/certs
  #   sudo curl -sLO https://packages.wazuh.com/${lib.versions.majorMinor version}/config.yml
  #   sudo curl -sLO https://packages.wazuh.com/${lib.versions.majorMinor version}/wazuh-certs-tool.sh
  #   sudo bash ./wazuh-certs-tool.sh --all
  #
  # That generates the certificate set under
  # `/var/lib/wazuh-stack/certs/wazuh-certificates/`. Move them up one
  # directory so the bind-mount paths above resolve:
  #
  #   sudo mv wazuh-certificates/* .
  #   sudo rm -rf wazuh-certificates*
  #   sudo chmod 750 /var/lib/wazuh-stack/certs
  #   sudo chmod 640 /var/lib/wazuh-stack/certs/*.pem
  #
  # Then `sudo nixos-rebuild switch` and the three containers come up.
  # Dashboard at https://<predator-LAN-IP>:443/.
}
