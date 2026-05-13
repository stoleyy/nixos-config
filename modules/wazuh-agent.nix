# Wazuh HIDS agent service.
#
# Default is disabled — enable per-host (see hosts/predator/default.nix).
# The agent is outbound-only: it initiates TCP 1514 (events) and TCP 1515
# (enrollment) to the manager. No inbound firewall rules are needed.
#
# Secret handling: the registration password lives in sops-nix
# (secrets/secrets.yaml: wazuh-agent-registration-password). The unit reads
# it via systemd LoadCredential, so it never appears in the Nix store and is
# not visible as a world-readable file.

{ pkgs, config, lib, ... }:

let
  cfg = config.services.wazuh-agent;

  ossecConf = pkgs.writeText "ossec.conf" ''
    <ossec_config>
      <client>
        <server>
          <address>${cfg.managerAddress}</address>
          <port>1514</port>
          <protocol>tcp</protocol>
        </server>
        <config-profile>${lib.concatStringsSep "," cfg.groups}</config-profile>
        <notify_time>10</notify_time>
        <time-reconnect>60</time-reconnect>
        <auto_restart>yes</auto_restart>
        <crypto_method>aes</crypto_method>
      </client>

      <client_buffer>
        <disabled>no</disabled>
        <queue_size>5000</queue_size>
        <events_per_second>500</events_per_second>
      </client_buffer>

      <logging>
        <log_format>plain</log_format>
      </logging>

      <syscheck>
        <disabled>no</disabled>
        <frequency>43200</frequency>
        <scan_on_start>yes</scan_on_start>
        <directories check_all="yes">/etc,/usr/bin,/usr/sbin</directories>
        <directories check_all="yes">/bin,/sbin,/boot</directories>
        <ignore>/etc/mtab</ignore>
        <ignore>/etc/random-seed</ignore>
      </syscheck>

      <rootcheck>
        <disabled>no</disabled>
      </rootcheck>

      <localfile>
        <log_format>journald</log_format>
        <location>journald</location>
      </localfile>
    </ossec_config>
  '';

  enrollScript = pkgs.writeShellScript "wazuh-agent-enroll" ''
    set -euo pipefail
    if [ ! -s /var/ossec/etc/client.keys ]; then
      ${cfg.package}/bin/agent-auth \
        -m "${cfg.managerAddress}" \
        -A "${cfg.agentName}" \
        -G "${lib.concatStringsSep "," cfg.groups}" \
        -P "$(cat "$CREDENTIALS_DIRECTORY/regpass")"
    fi
  '';

  daemonPath = lib.makeBinPath (with pkgs; [
    coreutils
    gnugrep
    iproute2
    nettools
    procps
    util-linux
  ]);

  mkDaemonUnit = name: ''wazuh-${name}'' // {};
in
{
  options.services.wazuh-agent = {
    enable = lib.mkEnableOption "Wazuh HIDS endpoint agent";

    package = lib.mkOption {
      type    = lib.types.package;
      default = pkgs.wazuh-agent;
      description = "The wazuh-agent package to use (provided by overlays/wazuh-agent.nix).";
    };

    managerAddress = lib.mkOption {
      type        = lib.types.str;
      example     = "wazuh.lan";
      description = "FQDN or IP of the Wazuh manager (typically reachable on the OPNsense LAN).";
    };

    agentName = lib.mkOption {
      type        = lib.types.str;
      default     = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Name registered with the manager; defaults to the host's networking.hostName.";
    };

    registrationPasswordFile = lib.mkOption {
      type        = lib.types.path;
      example     = lib.literalExpression "config.sops.secrets.wazuh-agent-registration-password.path";
      description = ''
        Path to a file containing the manager's registration password.
        Use sops-nix and reference the secret's `.path`. The file is loaded
        through systemd LoadCredential and never copied to the Nix store.
      '';
    };

    groups = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "default" ];
      description = "Agent groups passed to agent-auth -G and written into ossec.conf.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # /var/ossec is hardcoded in the Wazuh binaries; pre-create the tree with
    # restrictive ownership. The store-readable ossec.conf is then linked in
    # from the Nix store path.
    systemd.tmpfiles.rules = [
      "d /var/ossec               0750 root root - -"
      "d /var/ossec/etc           0750 root root - -"
      "d /var/ossec/logs          0750 root root - -"
      "d /var/ossec/queue         0750 root root - -"
      "d /var/ossec/queue/sockets 0750 root root - -"
      "d /var/ossec/queue/agents  0750 root root - -"
      "d /var/ossec/var           0750 root root - -"
      "d /var/ossec/var/run       0750 root root - -"
      "d /var/ossec/wodles        0750 root root - -"
      "d /var/ossec/ruleset       0750 root root - -"
      "d /var/ossec/active-response 0750 root root - -"
      "L+ /var/ossec/etc/ossec.conf - - - - ${ossecConf}"
    ];

    systemd.services.wazuh-agent = {
      description = "Wazuh HIDS agent (wazuh-agentd)";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network-online.target" ];
      wants       = [ "network-online.target" ];

      serviceConfig = {
        Type             = "simple";
        ExecStartPre     = "+${enrollScript}";
        ExecStart        = "${cfg.package}/bin/wazuh-agentd -f";
        LoadCredential   = "regpass:${cfg.registrationPasswordFile}";
        Restart          = "on-failure";
        RestartSec       = "10s";
        ReadWritePaths   = [ "/var/ossec" ];
        Environment      = [ "PATH=${daemonPath}" ];
      };
    };

    # Companion daemons — bound to the main agent unit so they start/stop
    # together. Each runs in foreground; do not call wazuh-control start —
    # it daemonizes children outside systemd's view.
    systemd.services.wazuh-execd = {
      description = "Wazuh execd (active-response handler)";
      bindsTo     = [ "wazuh-agent.service" ];
      partOf      = [ "wazuh-agent.service" ];
      after       = [ "wazuh-agent.service" ];
      wantedBy    = [ "wazuh-agent.service" ];
      serviceConfig = {
        Type           = "simple";
        ExecStart      = "${cfg.package}/bin/wazuh-execd -f";
        Restart        = "on-failure";
        ReadWritePaths = [ "/var/ossec" ];
        Environment    = [ "PATH=${daemonPath}" ];
      };
    };

    systemd.services.wazuh-logcollector = {
      description = "Wazuh logcollector";
      bindsTo     = [ "wazuh-agent.service" ];
      partOf      = [ "wazuh-agent.service" ];
      after       = [ "wazuh-agent.service" ];
      wantedBy    = [ "wazuh-agent.service" ];
      serviceConfig = {
        Type           = "simple";
        ExecStart      = "${cfg.package}/bin/wazuh-logcollector -f";
        Restart        = "on-failure";
        ReadWritePaths = [ "/var/ossec" ];
        Environment    = [ "PATH=${daemonPath}" ];
      };
    };

    systemd.services.wazuh-modulesd = {
      description = "Wazuh modulesd (inventory + remote commands)";
      bindsTo     = [ "wazuh-agent.service" ];
      partOf      = [ "wazuh-agent.service" ];
      after       = [ "wazuh-agent.service" ];
      wantedBy    = [ "wazuh-agent.service" ];
      serviceConfig = {
        Type           = "simple";
        ExecStart      = "${cfg.package}/bin/wazuh-modulesd -f";
        Restart        = "on-failure";
        ReadWritePaths = [ "/var/ossec" ];
        Environment    = [ "PATH=${daemonPath}" ];
      };
    };

    systemd.services.wazuh-syscheckd = {
      description = "Wazuh syscheckd (FIM + rootcheck)";
      bindsTo     = [ "wazuh-agent.service" ];
      partOf      = [ "wazuh-agent.service" ];
      after       = [ "wazuh-agent.service" ];
      wantedBy    = [ "wazuh-agent.service" ];
      serviceConfig = {
        Type           = "simple";
        ExecStart      = "${cfg.package}/bin/wazuh-syscheckd -f";
        Restart        = "on-failure";
        ReadWritePaths = [ "/var/ossec" ];
        Environment    = [ "PATH=${daemonPath}" ];
      };
    };
  };
}
