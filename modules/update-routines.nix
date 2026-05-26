# Unattended update pipeline — hands-off, Windows-style automatic maintenance.
{ config, pkgs, ... }:

# Three timers run weekly, fully unattended:
#   1. Sun 03:00 — `nix flake update --refresh` bumps flake.lock for all inputs
#      and commits the result directly to the current branch (main). No review
#      branch, no manual cherry-pick required.
#   2. Sun 04:00 — `nixos-rebuild boot` (system.autoUpgrade) builds the next
#      generation from the updated lock. allowReboot=false — the new generation
#      takes effect on the next conscious reboot. persistent=true ensures a
#      missed timer (e.g. system was off) catches up on next boot.
#   3. Sun 06:00 — vulnix scans the live closure for known CVEs; output in
#      journal: journalctl -u vulnix-scan
#   4. After nixos-upgrade.service — notify-reboot-needed sends a desktop
#      notification if a new generation was built and a reboot is pending.
#
# Wazuh and OPNsense are NOT auto-updated — both have plugin/version
# compatibility surfaces that require human eyeballs on release notes.
{
  # nh.clean (base.nix) handles store GC: --keep-since 7d --keep 5.
  # nix.gc is intentionally absent — both active simultaneously cause an eval conflict.

  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos";
    flags = [
      "-L" # full logs in journal
    ];
    dates = "Sun 04:00";
    randomizedDelaySec = "30min";
    persistent = true; # catch up missed timers on next boot
    allowReboot = false; # build only; reboot is a conscious choice
    operation = "boot"; # take effect on next reboot, not live
  };

  # Lock-file refresh on a separate schedule — runs before autoUpgrade so the
  # upgrade always builds from the freshest lock.
  # ---------- weekly CVE scan ----------
  # Runs after auto-upgrade completes, scanning the live closure for known CVEs.
  # Output goes to journal: journalctl -u vulnix-scan
  environment.systemPackages = [ pkgs.vulnix ];

  systemd = {
    timers = {
      "flake-lock-update" = {
        description = "Weekly nix flake update for /etc/nixos";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Sun 03:00";
          RandomizedDelaySec = "30min";
          Persistent = true;
        };
      };
      "vulnix-scan" = {
        description = "Weekly CVE scan of the running NixOS closure";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Sun 06:00";
          RandomizedDelaySec = "30min";
          Persistent = true;
        };
      };
    };

    services = {
      "vulnix-scan" = {
        description = "Scan running system closure for known CVEs (vulnix)";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.vulnix}/bin/vulnix -S";
        };
      };
      "flake-lock-update" = {
        description = "Refresh flake.lock and commit directly to current branch";
        # `nix flake update` on the /etc/nixos *git* flake shells out to `git`;
        # the systemd default PATH has no git, so the unit needs it explicitly.
        # `nix` itself is invoked by absolute path (same as elsewhere here).
        path = [ pkgs.git ];
        serviceConfig = {
          Type = "oneshot";
          WorkingDirectory = "/etc/nixos";
          ExecStart = pkgs.writeShellScript "flake-lock-update" ''
            set -euo pipefail
            cd /etc/nixos

            g() {
              git -c safe.directory=/etc/nixos \
                  -c user.name=nixos-auto \
                  -c user.email=nixos-auto@${config.networking.hostName} "$@"
            }

            /run/current-system/sw/bin/nix flake update --refresh

            if g diff --quiet -- flake.lock; then
              echo "flake.lock unchanged; nothing to do"
              exit 0
            fi

            g commit -m "flake.lock: weekly auto-update $(date -u +%Y-%m-%dT%H:%M:%SZ)" -- flake.lock
            echo "flake.lock updated and committed to $(g rev-parse --abbrev-ref HEAD)"
          '';
        };
      };

      "notify-reboot-needed" = {
        description = "Notify user when a reboot is needed after auto-upgrade";
        after = [ "nixos-upgrade.service" ];
        wantedBy = [ "nixos-upgrade.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "stoleyy";
        };
        environment.DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
        script = ''
          if [ "$(readlink /run/current-system)" != "$(readlink /nix/var/nix/profiles/system)" ]; then
            ${pkgs.libnotify}/bin/notify-send \
              --urgency=low \
              --icon=system-software-update \
              "System Update Ready" \
              "A new generation has been built. Reboot to apply."
          fi
        '';
      };

      # Post-boot health check — if the new generation has critical failures,
      # roll back the bootloader to the previous generation so the NEXT reboot
      # returns to a known-good state. This is a software-level substitute for
      # systemd-boot bootCounting (not yet in NixOS 25.11 stable).
      "boot-health-check" = {
        description = "Post-boot health check — auto-rollback on critical failures";
        after = [
          "multi-user.target"
          "graphical.target"
        ];
        wantedBy = [ "graphical.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          sleep 10 # brief settle; graphical.target ordering handles most deps

          FAILED=$(systemctl --failed --no-legend | wc -l)
          BOOTED=$(readlink /run/booted-system)
          CURRENT=$(readlink /run/current-system)

          echo "Boot health check: $FAILED failed units"
          echo "  booted:  $BOOTED"
          echo "  current: $CURRENT"

          if [ "$FAILED" -gt 3 ]; then
            echo "CRITICAL: $FAILED units failed — rolling back bootloader to previous generation"
            /run/current-system/sw/bin/nixos-rebuild boot --rollback 2>&1 || true
            ${pkgs.libnotify}/bin/notify-send \
              --urgency=critical \
              --icon=dialog-warning \
              "System Rolled Back" \
              "$FAILED units failed after boot. Next reboot will use the previous generation." \
              2>/dev/null || true
          else
            echo "Boot healthy — $FAILED failed units (threshold: 3)"
          fi
        '';
      };
    };
  };
}
