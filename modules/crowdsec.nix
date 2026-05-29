# CrowdSec — automated, behavioral intrusion detection + response.
#
# Runs a self-contained local API (no enrollment / cloud account required) and
# parses the systemd journal for authentication abuse (sudo/su/PAM brute force,
# etc.). The default remediation profiles ship with the module, so detected
# attackers are added to a local decision list automatically.
#
# This box exposes almost no inbound surface (no sshd, media WebUIs are
# localhost-only), so CrowdSec's value here is host-local auth-abuse detection
# and the community blocklist via the daily hub update — not edge filtering.
# A firewall bouncer can be layered later (services.crowdsec-firewall-bouncer)
# if inbound services are ever opened.
#
# Disabled in the gaming-tuned specialisation (see hosts/predator/default.nix).
{ lib, ... }:

{
  services.crowdsec = {
    enable = true;
    # Daily `cscli hub update` so parsers/scenarios/blocklists stay current.
    autoUpdateService = true;

    # Install the Linux collection: syslog parsers + base brute-force scenarios
    # that consume the journald acquisition below.
    hub.collections = [ "crowdsecurity/linux" ];

    # Enable the local LAPI server (agent + server in one process, no cloud
    # enrollment). Without this the module leaves credentials_path = null and
    # never runs `cscli machines add --auto`, so the ExecStartPre config-test
    # fails on every boot.
    settings.general.api.server.enable = true;
    # Path where crowdsec-setup writes (and crowdsec reads) the auto-generated
    # LAPI client credentials on first start.
    settings.lapi.credentialsFile = "/var/lib/crowdsec/local_api_credentials.yaml";

    # Data source: the authpriv slice of the journal (sudo, su, PAM, login).
    # The crowdsec service user is auto-added to systemd-journal by the module,
    # so no extra access wiring is needed.
    localConfig.acquisitions = [
      {
        source = "journalctl";
        journalctl_filter = [ "SYSLOG_FACILITY=10" ];
        labels.type = "syslog";
      }
    ];
  };

  # Upstream nixpkgs bug: crowdsec-update-hub runs with DynamicUser + PrivateUsers,
  # so its ExecStartPost `systemctl reload crowdsec.service` fails with
  # "Access denied" (polkit requires interactive auth in that sandbox).
  # Suppress the reload — hub content is picked up on the next crowdsec restart.
  systemd.services.crowdsec-update-hub.serviceConfig.ExecStartPost = lib.mkForce "";
}
