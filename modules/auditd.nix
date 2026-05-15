_:

# Linux audit subsystem — kernel-level syscall observability for Wazuh.
#
# Wazuh's File Integrity Monitoring (FIM) and several rule groups depend on
# auditd's structured output. Without auditd, Wazuh only sees syslog and
# can't correlate things like "process X opened /etc/shadow."
#
# Rule selection follows the Linux Audit / NIST / MITRE-tagged subset that
# Wazuh's stock rules can ingest. Keep this list TIGHT — every rule has a
# per-event CPU and log cost. The four below cover the highest-signal cases
# for a single-user workstation; expand only when triaging a specific concern.
{
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    backlogLimit = 8192;
    failureMode = "printk"; # don't panic on full buffer; just log
    rules = [
      # Track modifications to authentication state. NixOS-only path set:
      # /etc/gshadow and /etc/sudoers.d/ do NOT exist here (NixOS manages
      # users via passwd/group/shadow and compiles all sudo policy into
      # /etc/sudoers). auditctl -R rejects a watch on a missing path and
      # fails the whole unit, so only real paths are listed.
      "-w /etc/passwd  -p wa -k identity"
      "-w /etc/shadow  -p wa -k identity"
      "-w /etc/group   -p wa -k identity"
      "-w /etc/sudoers -p wa -k identity"

      # Privilege escalations via SUID/SGID binary execution (filtered to
      # interactive UIDs only — uid>=1000 excludes daemons and kernel).
      "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -k privileged-exec"

      # Sensitive command auditing — only the binaries that matter for
      # incident response on this kind of box. NixOS has no /usr/bin; the
      # real sudo is the setuid wrapper under /run/wrappers/bin. The
      # /etc/ssh/sshd_config watch is dropped too — openssh is not enabled
      # on this host so the file does not exist (re-add the watch if/when
      # services.openssh is turned on).
      "-w /run/wrappers/bin/sudo -p x -k sudo-exec"

      # Module loads / unloads — kernel-level changes need eyes on them.
      "-a always,exit -F arch=b64 -S init_module,delete_module,finit_module -k modules"

      # Make the audit configuration itself immutable until next boot.
      # Keep this LAST — anything after it is silently dropped.
      "-e 2"
    ];
  };
}
