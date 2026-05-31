# Host file-integrity baseline (AIDE).
#
# The defender-side of the forensic hashing/integrity theme: a cryptographic
# baseline of high-signal, low-churn paths — crucially the UNENCRYPTED /boot
# (the evil-maid / dead-box surface a forensic examiner images first) — so
# at-rest or post-compromise tampering of the kernel, initrd, bootloader, or
# system config becomes detectable. auditd (modules/auditd.nix) catches live
# syscalls; this adds the offline baseline auditd lacks.
#
# Complements (does not replace) the Wazuh FIM in modules/wazuh-agent.nix,
# which is blocked on manager/cert bootstrap. AIDE is self-contained and needs
# no external infra. nixpkgs 25.11 ships aide 0.19.2 with NO `services.aide`
# module (verified), so this is wired with custom units.
#
# Alerts surface two ways: a priority-err line to the journal (captured by the
# journald + Vector pipeline in modules/monitoring.nix) and a best-effort
# desktop notification. The check never fails its unit, to stay decoupled from
# the boot-health-check auto-rollback heuristic in modules/update-routines.nix.
#
# After an INTENDED system change (nixos-rebuild switch rewrites /etc, kernel
# bumps rewrite /boot) the baseline is expected to drift — re-baseline with:
#   sudo systemctl start aide-update
{ pkgs, ... }:

let
  dbDir = "/var/lib/aide";
  db = "${dbDir}/aide.db"; # baseline (database_in)
  dbNew = "${dbDir}/aide.db.new"; # written by --init / --update (database_out)

  aideConf = pkgs.writeText "aide.conf" ''
    database_in=file:${db}
    database_out=file:${dbNew}
    gzip_dbout=no
    report_url=stdout
    report_summarize_changes=yes

    # Attribute groups
    Full    = p+ftype+i+n+u+g+s+b+m+c+sha256
    Content = p+ftype+u+g+s+sha256

    # ── Monitored paths ──
    # /boot is the prime target: unencrypted ESP holding kernel + initrd +
    # bootloader. Full attributes incl. hashes.
    /boot Full
    # System config + root's home — on the encrypted root, so this is about
    # detecting live post-compromise tampering rather than at-rest recovery.
    /etc  Content
    /root Content
    # High-signal user config (skip noisy/large trees like .gnupg trustdb).
    /home/stoleyy/.ssh    Content
    /home/stoleyy/.bashrc Content

    # ── Exclusions (volatile / huge / encrypted-data we don't baseline) ──
    !/var
    !/nix
    !/proc
    !/sys
    !/dev
    !/run
    !/tmp
    !/home/stoleyy/games
    !/data
    !/etc/resolv\.conf$
    !/etc/mtab$
    !/etc/\.clean$
    !/etc/\.pwd\.lock$
    !/etc/adjtime$
  '';
in
{
  environment.systemPackages = [ pkgs.aide ];

  # Expose the config so an operator can run `aide --check -c /etc/aide/aide.conf`.
  environment.etc."aide/aide.conf".source = aideConf;

  systemd.services = {
    # One-time baseline build. Guarded so it only runs when no baseline exists.
    aide-init = {
      description = "AIDE — initialize file-integrity baseline";
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "!${db}";
      path = [
        pkgs.aide
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "aide";
        StateDirectoryMode = "0700";
      };
      script = ''
        aide --init --config=/etc/aide/aide.conf
        mv -f ${dbNew} ${db}
        echo "AIDE: baseline initialized at ${db}"
      '';
    };

    # Periodic integrity check (driven by the timer below).
    aide-check = {
      description = "AIDE — file-integrity check";
      after = [ "aide-init.service" ];
      path = [
        pkgs.aide
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "aide";
        StateDirectoryMode = "0700";
      };
      script = ''
        if [ ! -e ${db} ]; then
          echo "<4>AIDE: no baseline yet — run 'systemctl start aide-init'"
          exit 0
        fi
        rc=0
        aide --check --config=/etc/aide/aide.conf || rc=$?
        if [ "$rc" -eq 0 ]; then
          echo "AIDE: integrity check clean"
        else
          echo "<3>AIDE: integrity DIFFERENCES detected (exit $rc) — see report above. If this change was intended, re-baseline with 'systemctl start aide-update'."
          ${pkgs.libnotify}/bin/notify-send --urgency=critical --icon=dialog-warning \
            "AIDE integrity alert" \
            "File-integrity differences detected (exit $rc). Review: journalctl -u aide-check" \
            2>/dev/null || true
        fi
        # Always succeed: alerting is via the journal/notify above, decoupled
        # from the boot-health-check failed-unit rollback heuristic.
        exit 0
      '';
    };

    # Manual re-baseline after an intended system change.
    aide-update = {
      description = "AIDE — re-baseline (accept current filesystem state)";
      path = [
        pkgs.aide
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "aide";
        StateDirectoryMode = "0700";
      };
      script = ''
        # --update exits non-zero when differences exist (expected when
        # re-baselining); take the freshly written DB regardless.
        aide --update --config=/etc/aide/aide.conf || true
        mv -f ${dbNew} ${db}
        echo "AIDE: baseline updated at ${db}"
      '';
    };
  };

  systemd.timers.aide-check = {
    description = "AIDE — daily file-integrity check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
