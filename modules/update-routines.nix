_:

# Periodic update wiring so the system doesn't slowly turn into a
# fossilized snapshot. Two timers:
#   1. Weekly `nixos-rebuild boot` — pulls /etc/nixos from main and builds
#      the next generation. Manual reboot still required (allowReboot=false).
#   2. Weekly `nix flake update` — bumps flake.lock for nixpkgs / home-manager
#      / other inputs. Commits the updated lock file to a branch named
#      `auto/flake-update-$(date)` for review (NOT pushed automatically).
#
# Wazuh and OPNsense are NOT auto-updated — both have plugin/version
# compatibility surfaces that require human eyeballs on release notes.
{
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
  # the resulting lock to a branch for review.
  systemd.timers."flake-lock-update" = {
    description = "Weekly nix flake update for /etc/nixos";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
  systemd.services."flake-lock-update" = {
    description = "Update flake.lock and stage on a branch";
    path = with builtins; [ ];
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/etc/nixos";
      ExecStart = "/run/current-system/sw/bin/nix flake update --refresh";
    };
  };
}
