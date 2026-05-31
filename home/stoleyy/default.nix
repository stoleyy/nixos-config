{
  pkgs,
  lib,
  osConfig,
  host,
  ...
}:

{
  imports = [
    ./shell.nix
    ./ai.nix
    ./openhuman.nix
    ./claude-proxy.nix
    ./editor.nix
    ./browser.nix
    ./git.nix
    ./gpg.nix
    ./audio.nix
    ./hyprland.nix
    ./waybar.nix
    ./rofi.nix
    ./swaync.nix
    ./wlogout.nix
    ./gtk.nix
    ./plasma.nix
    ./spicetify.nix
    ./ghostty.nix
    ./mpv.nix
  ];

  home = {
    username = "stoleyy";
    homeDirectory = "/home/stoleyy";
    stateVersion = "25.11";

    file.".local/share/color-schemes/DeltaruneSanctuary.colors".source = ./deltarune-sanctuary.colors;

    # Force-clear stale kdeglobals color cache. Plasma-manager declares
    # DeltaruneSanctuary but kdeglobals accumulates runtime color state
    # that overrides the declared scheme (right-click menus, Qt apps stay
    # stale colors). Removing it lets plasma-manager write a clean copy.
    # Gated on the plasma specialisation — kdeglobals is Plasma-only, so this
    # is a no-op in the pure-Hyprland default generation.
    activation = {
      fixKdeColors = lib.mkIf osConfig.modules.plasma.enable (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          rm -f "$HOME/.config/kdeglobals"
        ''
      );

    # Pre-seed rofi drun cache so Ghostty appears first in Super+Space.
    # Short-circuits once the entry is already pinned at 100, so the common
    # case touches nothing on every rebuild.
    activation.pinGhosttyInRofi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cache="$HOME/.cache/rofi3.druncache"
      entry="com.mitchellh.ghostty.desktop"
      if [ -f "$cache" ] && grep -qx "100 $entry" "$cache"; then
        : # already pinned — nothing to do
      elif grep -q " $entry$" "$cache" 2>/dev/null; then
        ${pkgs.gnused}/bin/sed -i "s/^[0-9]* $entry$/100 $entry/" "$cache"
      else
        mkdir -p "$(dirname "$cache")"
        echo "100 $entry" >> "$cache"
      fi
    '';

      # Seed qBittorrent.conf with performance tuning, VPN interface binding,
      # AutoRun (game-install pipeline), and WebUI for NAT-PMP port push.
      #
      # Uses a line-oriented Python merge that only sets known scalar keys and
      # preserves qBit's @Variant(...) blobs and runtime state verbatim.
      # Idempotent — runs every activation, creates the file if absent.
      #
      # IMPORTANT: qBit reads the conf at startup and overwrites it on clean exit.
      # Close qBittorrent BEFORE `nixos-rebuild switch`, or restart it after, so
      # the seeded values take effect.
      seedQbittorrentConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.python3}/bin/python3 - <<'PYEOF'
        import os, tempfile

        CONF = os.path.expanduser("~/.config/qBittorrent/qBittorrent.conf")

        # Keys to seed: (section, key, value)
        SEEDS = [
            # --- Legal ---
            ("LegalNotice", "Accepted", "true"),
            # --- WebUI (required for NAT-PMP port push) ---
            ("Preferences", r"WebUI\Enabled", "true"),
            ("Preferences", r"WebUI\Address", "127.0.0.1"),
            ("Preferences", r"WebUI\Port", "8181"),
            ("Preferences", r"WebUI\LocalHostAuth", "false"),
            ("Preferences", r"WebUI\HostHeaderValidation", "true"),
            # --- VPN interface bind (fail-closed) ---
            ("Preferences", r"Connection\Interface", "protonvpn"),
            ("Preferences", r"Connection\InterfaceName", "protonvpn"),
            ("BitTorrent", r"Session\Interface", "protonvpn"),
            ("BitTorrent", r"Session\InterfaceName", "protonvpn"),
            ("BitTorrent", r"Session\Port", "6881"),
            ("BitTorrent", r"Session\UseRandomPort", "false"),
            # --- Disable qBit's built-in UPnP/NAT-PMP (our service is authoritative) ---
            ("Preferences", r"Connection\PortForwardingEnabled", "false"),
            # --- Peer discovery (public swarms via VPN — no real-IP leak) ---
            ("BitTorrent", r"Session\DHTEnabled", "true"),
            ("BitTorrent", r"Session\PeXEnabled", "true"),
            ("BitTorrent", r"Session\LSDEnabled", "false"),
            ("BitTorrent", r"Session\Encryption", "0"),
            ("BitTorrent", r"Session\AnonymousModeEnabled", "false"),
            # --- libtorrent 2.x performance tuning ---
            ("BitTorrent", r"Session\AsyncIOThreadsCount", "32"),
            ("BitTorrent", r"Session\HashingThreadsCount", "4"),
            ("BitTorrent", r"Session\FilePoolSize", "5000"),
            ("BitTorrent", r"Session\DiskQueueSize", "16777216"),
            ("BitTorrent", r"Session\SendBufferWatermark", "5120"),
            ("BitTorrent", r"Session\SendBufferWatermarkFactor", "200"),
            ("BitTorrent", r"Session\ConnectionSpeed", "100"),
            ("BitTorrent", r"Session\SocketBacklogSize", "300"),
            ("BitTorrent", r"Session\MaxConnections", "2000"),
            ("BitTorrent", r"Session\MaxConnectionsPerTorrent", "500"),
            ("BitTorrent", r"Session\MaxUploads", "50"),
            ("BitTorrent", r"Session\MaxUploadsPerTorrent", "16"),
            ("BitTorrent", r"Session\uTPRateLimited", "false"),
            ("BitTorrent", r"Session\QueueingSystemEnabled", "false"),
            # --- Download paths (same ext4 volume = rename, not copy) ---
            # qBit 5.x reads these from [BitTorrent] (Session\*), NOT [Preferences].
            ("BitTorrent", r"Session\TempPathEnabled", "true"),
            ("BitTorrent", r"Session\TempPath", "${host.gamesDir}/.downloads/incomplete"),
            ("BitTorrent", r"Session\DefaultSavePath", "${host.gamesDir}/.downloads/complete"),
            # --- AutoRun: game-install pipeline (survives config resets) ---
            ("AutoRun", "enabled", "true"),
            ("AutoRun", "program", 'game-install "%F" "%N"'),
        ]

        os.makedirs(os.path.dirname(CONF), exist_ok=True)

        # Read existing conf (or start empty)
        lines = []
        if os.path.isfile(CONF):
            with open(CONF) as f:
                lines = f.readlines()

        # Build index: section -> key -> line index
        current_section = None
        section_ends = {}   # section -> last line index in that section
        key_index = {}      # (section, key) -> line index
        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                current_section = stripped[1:-1]
            elif "=" in stripped and current_section:
                k = stripped.split("=", 1)[0].rstrip()
                key_index[(current_section, k)] = i
            if current_section:
                section_ends[current_section] = i

        changed = False
        for section, key, value in SEEDS:
            target = f"{key}={value}\n"
            if (section, key) in key_index:
                idx = key_index[(section, key)]
                if lines[idx].rstrip() != target.rstrip():
                    lines[idx] = target
                    changed = True
            elif section in section_ends:
                # Append after last line of existing section
                ins = section_ends[section] + 1
                lines.insert(ins, target)
                # Re-index after insertion
                for s in section_ends:
                    if section_ends[s] >= ins:
                        section_ends[s] += 1
                for sk in list(key_index):
                    if key_index[sk] >= ins:
                        key_index[sk] += 1
                key_index[(section, key)] = ins
                section_ends[section] = ins
                changed = True
            else:
                # Create new section at end of file
                lines.append(f"\n[{section}]\n")
                lines.append(target)
                idx = len(lines) - 1
                section_ends[section] = idx
                key_index[(section, key)] = idx
                changed = True

        if changed:
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(CONF))
            with os.fdopen(fd, "w") as f:
                f.writelines(lines)
            os.replace(tmp, CONF)
        PYEOF
      '';
    };

    packages = with pkgs; [
      qbittorrent
      keepassxc
      claude-code
      dwt1-shell-color-scripts
    ];
  };

  programs.home-manager.enable = true;
}
