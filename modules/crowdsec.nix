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
_:

{
  services.crowdsec = {
    enable = true;
    # Daily `cscli hub update` so parsers/scenarios/blocklists stay current.
    autoUpdateService = true;

    # Install the Linux collection: syslog parsers + base brute-force scenarios
    # that consume the journald acquisition below.
    hub.collections = [ "crowdsecurity/linux" ];

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
}
