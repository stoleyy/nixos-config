# Linux audit subsystem — kernel syscall/FIM observability feeding Wazuh HIDS.
_:

# Linux audit subsystem — kernel-level syscall observability for Wazuh.
#
# Wazuh's File Integrity Monitoring (FIM) and several rule groups depend on
# auditd's structured output. Without auditd, Wazuh only sees syslog and
# can't correlate things like "process X opened /etc/shadow."
#
# Rule selection follows the Linux Audit / NIST / MITRE-tagged subset that
# Wazuh's stock rules can ingest. Keep this list TIGHT — every rule has a
# per-event CPU and log cost.
#
# Hard-won notes from on-box debugging (the generated file is
# `-D / -b / -f / -r` preamble ++ these rules ++ a module-appended `-e 1`):
#
#   * Every `-w` path must exist *at the moment audit-rules-nixos.service
#     runs in early boot*, or `auditctl -R` aborts the whole load. NixOS
#     has no /usr/bin, /etc/gshadow, /etc/sudoers.d, and (here) no
#     /etc/ssh/sshd_config — all removed. /run/wrappers/bin/sudo *does*
#     exist post-boot but NOT yet when audit loads (the setuid wrappers
#     are created later), so that watch also fails ENOENT — removed.
#     sudo execution is still covered by the privileged-exec execve rule
#     below (euid=0 + interactive auid), which is the real signal anyway.
#
#   * Do NOT put `-e 2` (immutable) here. NixOS's audit module appends its
#     own `-e 1` after this list; `-e 2` then makes that trailing `-e 1`
#     fail ("immutable mode, no rule changes allowed") AND, because `-e 2`
#     still applies on a partial/failed load, it locks audit until the
#     next reboot and masks the real first error on every subsequent
#     switch. Immutable audit is also incompatible with the
#     declarative nixos-rebuild workflow. Leave audit mutable (`-e 1`,
#     set by the module).
{
  security.auditd.enable = false;
  security.audit = {
    enable = false;
    backlogLimit = 8192;
    failureMode = "printk"; # don't panic on full buffer; just log
    rules = [
      # Authentication-state files. Only paths NixOS actually creates and
      # that exist early enough for the audit load (/etc is set up before
      # this service runs).
      "-w /etc/passwd  -p wa -k identity"
      "-w /etc/shadow  -p wa -k identity"
      "-w /etc/group   -p wa -k identity"
      "-w /etc/sudoers -p wa -k identity"

      # Privilege escalation via SUID/SGID exec, interactive UIDs only
      # (auid>=1000 excludes daemons/kernel). This also captures sudo
      # invocations, so a dedicated sudo-binary watch is redundant.
      "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -k privileged-exec"

      # Kernel module load/unload.
      "-a always,exit -F arch=b64 -S init_module,delete_module,finit_module -k modules"

      # Failed access attempts (EACCES/EPERM = exploitation/recon signal).
      "-a always,exit -F arch=b64 -S open,openat,creat -F exit=-EACCES -F auid>=1000 -F auid!=-1 -k access-denied"
      "-a always,exit -F arch=b64 -S open,openat,creat -F exit=-EPERM  -F auid>=1000 -F auid!=-1 -k access-denied"

      # File attribute / ACL tampering.
      "-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=-1 -k file-attr"
      "-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=-1 -k file-perm"
      "-a always,exit -F arch=b64 -S fchownat,fchown,chown,lchown -F auid>=1000 -F auid!=-1 -k file-perm"

      # Mount operations (filesystem manipulation).
      "-a always,exit -F arch=b64 -S mount,umount2 -F auid>=1000 -F auid!=-1 -k mounts"

      # Time changes — no auid filter; any-context time manipulation is suspicious.
      "-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change"

      # Privilege boundary (uid/gid changes).
      "-a always,exit -F arch=b64 -S setuid,setgid,setresuid,setresgid,setfsuid,setfsgid -F auid>=1000 -F auid!=-1 -k priv-boundary"
    ];
  };
}
