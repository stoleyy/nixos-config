{ pkgs, ... }:

# Periodic update wiring so the system doesn't slowly turn into a
# fossilized snapshot. Two timers:
#   1. Weekly `nixos-rebuild boot` — pulls /etc/nixos from main and builds
#      the next generation. Manual reboot still required (allowReboot=false).
#   2. Weekly `nix flake update` — bumps flake.lock for nixpkgs / home-manager
#      / other inputs, then commits the updated lock to a branch named
#      `auto/flake-update-<timestamp>` for review (NOT pushed automatically;
#      /etc/nixos is left back on its original branch, working tree clean).
#   3. Weekly nix GC — deletes store paths older than 14 days. Keeps recent
#      generations for rollback while preventing unbounded disk growth.
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
      "--update-input"
      "nixpkgs"
      "--no-write-lock-file"
      "-L" # full logs in journal
    ];
    dates = "Sun 04:00";
    randomizedDelaySec = "30min";
    allowReboot = false; # build only; reboot is a conscious choice
    operation = "boot"; # take effect on next reboot, not live
  };

  # Lock-file refresh on a separate schedule. system.autoUpgrade above
  # uses --update-input nixpkgs (single input). For a full multi-input
  # refresh, run `nix flake update` weekly via systemd timer and stash
  # the resulting lock on a review branch.
  systemd.timers."flake-lock-update" = {
    description = "Weekly nix flake update for /etc/nixos";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
  # Flatpak auto-update: weekly, after the flake-lock-update timer.
  # Steam (Flatpak) and any other Flatpak apps stay current without manual pulls.
  systemd.timers."flatpak-update" = {
    description = "Weekly Flatpak update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 05:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
  systemd.services."flatpak-update" = {
    description = "Update all Flatpak applications";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.flatpak}/bin/flatpak update -y --noninteractive";
    };
  };

  # ---------- weekly CVE scan ----------
  # Runs after auto-upgrade completes, scanning the live closure for known CVEs.
  # Output goes to journal: journalctl -u vulnix-scan
  environment.systemPackages = [ pkgs.vulnix ];
  systemd.timers."vulnix-scan" = {
    description = "Weekly CVE scan of the running NixOS closure";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 06:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
  systemd.services."vulnix-scan" = {
    description = "Scan running system closure for known CVEs (vulnix)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.vulnix}/bin/vulnix -S";
    };
  };

  systemd.services."flake-lock-update" = {
    description = "Refresh flake.lock and commit it to a review branch";
    # `nix flake update` on the /etc/nixos *git* flake shells out to `git`;
    # the systemd default PATH has no git, so the unit needs it explicitly.
    # `nix` itself is invoked by absolute path (same as elsewhere here).
    path = [ pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/etc/nixos";
      # Refresh the lock, and if it actually changed, park the change on a
      # dated review branch without disturbing the branch /etc/nixos is on
      # (the user's normal `git pull origin main` workflow stays clean).
      # Not pushed — a human reviews `git log auto/flake-update-*` and
      # cherry-picks / fast-forwards deliberately.
      ExecStart = pkgs.writeShellScript "flake-lock-update" ''
        set -euo pipefail
        cd /etc/nixos

        g() {
          git -c safe.directory=/etc/nixos \
              -c user.name=nixos-auto \
              -c user.email=nixos-auto@predator "$@"
        }

        orig=$(g rev-parse --abbrev-ref HEAD)

        /run/current-system/sw/bin/nix flake update --refresh

        if g diff --quiet -- flake.lock; then
          echo "flake.lock unchanged; nothing to do"
          exit 0
        fi

        br="auto/flake-update-$(date +%Y%m%d-%H%M%S)"
        g checkout -b "$br"
        g commit -m "flake.lock: weekly auto-update $(date -u +%Y-%m-%dT%H:%M:%SZ)" -- flake.lock
        g checkout "$orig"
        echo "updated flake.lock committed to branch $br (not pushed); /etc/nixos back on $orig"
      '';
    };
  };
}
