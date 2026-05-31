# W1/W2 containment — dedicated low-privilege "gamer" account.
#
# The Steam gaming-mode (gaming-tuned) session runs as `gamer` instead of
# `stoleyy`, so untrusted cracked games (FitGirl/DODI repacks via Wine/Proton)
# execute with NO access to stoleyy's $HOME — the Brave vault profile,
# KeePassXC .kdbx, SSH/GPG keys, and sops-decryptable material. A malicious
# game can compromise the throwaway `gamer` account, not your identity.
#
# This only changes the gaming-tuned boot entry (a separate, reversible
# specialisation). The normal Hyprland session as stoleyy is untouched — if the
# gamer session misbehaves, boot the default entry and everything is as before.
#
# A true VM/hypervisor (cracked game in a guest, GPU passed through) is a
# strictly stronger boundary; this UID split is the no-extra-hardware version.
#
# ── ON-BOX FOLLOW-UPS (not declarative / not CI-validatable) ──
#   1. Boot gaming mode once and log into Steam AS gamer — gamer has its own
#      (empty) library; cracked games live at /games (shared, see below).
#   2. Point game-install's Steam target at gamer's userdata
#      (/home/gamer/.local/share/Steam/userdata) so new installs appear in
#      gamer's Big Picture. Left out here to avoid colliding with PR #60's edit
#      to packages/game-install.nix.
#   3. Whatever user runs game-install (qBittorrent's "run external program")
#      must be in the `games` group to write the library (it is group-writable,
#      setgid, below). stoleyy is added here; add the qbittorrent user too if
#      the pipeline runs under that service.
{ host, ... }:

{
  users = {
    groups.gamer = { };
    # Shared group for the games library so stoleyy (installs) and gamer (plays)
    # both reach it — without gamer being able to read the rest of stoleyy's home.
    groups.games = { };

    users.gamer = {
      isNormalUser = true;
      description = "Low-privilege gaming account (untrusted-code containment)";
      home = "/home/gamer";
      createHome = true;
      # GPU + audio + controllers + GameMode only. Deliberately NOT in wheel,
      # networkmanager, media, untrusted, or any of stoleyy's groups.
      extraGroups = [
        "video"
        "render"
        "audio"
        "input"
        "gamemode"
        "games"
      ];
    };

    # stoleyy joins `games` so the install pipeline can populate the library.
    users.${host.user}.extraGroups = [ "games" ];
  };

  # Expose the games library at a neutral top-level path the gamer account can
  # reach. gamer cannot enter /home/stoleyy (stays 0700), but / is traversable,
  # so /games (a bind mount of the same data, group-shared) gives gamer the
  # library without exposing anything else in stoleyy's home.
  fileSystems."/games" = {
    device = host.gamesDir;
    options = [
      "bind"
      "x-systemd.requires-mounts-for=${host.gamesDir}"
      "nofail"
    ];
  };
}
