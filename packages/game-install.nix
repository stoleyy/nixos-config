{
  writeShellApplication,
  wineWowPackages,
  python3,
  rsync,
  findutils,
  libnotify,
  procps,
  systemd,
  host,
}:
writeShellApplication {
  name = "game-install";

  runtimeInputs = [
    wineWowPackages.stable
    (python3.withPackages (p: [ p.vdf ]))
    rsync
    findutils
    libnotify # notify-send
    procps # pgrep
    systemd # systemd-cat
  ];

  excludeShellChecks = [
    "SC2012" # find -printf flagged by shellcheck but correct here
    "SC2016" # single-quoted heredoc contains $vars intentionally
  ];

  text = ''
    # game-install <save_path> <torrent_name>
    # Called by qBittorrent on torrent completion.
    # Installs the game (repack via Wine or pre-extracted via rsync),
    # finds the main .exe, and registers it as a Steam non-Steam shortcut.

    SAVE_PATH="$1"
    TORRENT_NAME="$2"
    GAMES_DIR="${host.gamesDir}"
    STEAM_USERDATA="$HOME/.local/share/Steam/userdata"

    # Validate prerequisites
    if [ ! -d "$GAMES_DIR" ]; then
      systemd-cat -t game-install -p err echo "Games volume not mounted: $GAMES_DIR"
      exit 1
    fi

    # Auto-detect Steam ID (first numeric directory in userdata/)
    STEAM_ID=$(find "$STEAM_USERDATA" -maxdepth 1 -mindepth 1 -type d \
               -printf "%f\n" | sort | head -1)
    if [ -z "$STEAM_ID" ]; then
      systemd-cat -t game-install -p err echo "No Steam userdata found"
      exit 1
    fi
    SHORTCUTS="$STEAM_USERDATA/$STEAM_ID/config/shortcuts.vdf"

    # --- Step 1: Sanitize game name ---
    GAME_NAME="$TORRENT_NAME"
    # Strip scene/repack group tags
    GAME_NAME=$(echo "$GAME_NAME" | sed -E \
      's/[._-]*(FitGirl|DODI|EMPRESS|CPY|CODEX|SKIDROW|RELOADED|GOG|REPACK)[._-]*//gi')
    GAME_NAME=$(echo "$GAME_NAME" | sed -E 's/[._-]*MULTI[0-9]+[._-]*//gi')
    # Strip version patterns
    GAME_NAME=$(echo "$GAME_NAME" | sed -E 's/[._-]*v[0-9]+(\.[0-9]+)*[._-]*//gi')
    GAME_NAME=$(echo "$GAME_NAME" | sed -E 's/[._-]*\[[0-9]+(\.[0-9]+)*\][._-]*//gi')
    GAME_NAME=$(echo "$GAME_NAME" | sed -E 's/[._-]*Build\.[0-9]+[._-]*//gi')
    # Strip edition tags
    GAME_NAME=$(echo "$GAME_NAME" | sed -E \
      's/[._-]*(Deluxe|Gold|GOTY|Complete|Ultimate)[._-]*Edition//gi')
    GAME_NAME=$(echo "$GAME_NAME" | sed -E 's/[._-]*Directors[._]Cut[._-]*//gi')
    # Strip architecture tags
    GAME_NAME=$(echo "$GAME_NAME" | sed -E 's/[._-]*\([0-9]+bit\)[._-]*//gi')
    GAME_NAME=$(echo "$GAME_NAME" | sed -E 's/[._-]*\(x(64|86)\)[._-]*//gi')
    # Normalize separators, collapse spaces, trim
    GAME_NAME=$(echo "$GAME_NAME" | tr '._-' ' ' | tr -s ' ' | sed 's/^ //;s/ $//')
    [ -z "$GAME_NAME" ] && GAME_NAME="$TORRENT_NAME"

    INSTALL_DIR="$GAMES_DIR/$GAME_NAME"
    systemd-cat -t game-install -p info echo "Processing: $GAME_NAME"

    # --- Step 2: Detect install type ---
    SETUP_EXE=$(find "$SAVE_PATH" -maxdepth 2 -iname "setup.exe" | head -1)

    if [ -n "$SETUP_EXE" ]; then
      # --- Step 3a: Repack — run Windows installer silently via Wine ---
      systemd-cat -t game-install -p info echo "Repack detected: $SETUP_EXE"
      mkdir -p "$INSTALL_DIR"
      wine "$SETUP_EXE" /SILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS \
           /DIR="$INSTALL_DIR" &
      WINE_PID=$!

      ELAPSED=0
      while kill -0 "$WINE_PID" 2>/dev/null; do
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        if [ "$ELAPSED" -ge 1800 ]; then
          kill "$WINE_PID" 2>/dev/null || true
          systemd-cat -t game-install -p err echo "Installer timeout: $GAME_NAME"
          exit 1
        fi
      done
      wait "$WINE_PID" || true
    else
      # --- Step 3b: Pre-extracted — rsync into games directory ---
      systemd-cat -t game-install -p info echo "Pre-extracted, moving to $INSTALL_DIR"
      mkdir -p "$INSTALL_DIR"
      rsync -a --remove-source-files "$SAVE_PATH/" "$INSTALL_DIR/"
    fi

    # --- Step 4: Find main executable ---
    EXE=""
    if   [ -f "$INSTALL_DIR/$GAME_NAME.exe" ]; then EXE="$INSTALL_DIR/$GAME_NAME.exe"
    elif [ -f "$INSTALL_DIR/game.exe"        ]; then EXE="$INSTALL_DIR/game.exe"
    elif [ -f "$INSTALL_DIR/launch.exe"      ]; then EXE="$INSTALL_DIR/launch.exe"
    else
      # Largest .exe in the root only (avoids _CommonRedist/, DirectX/ etc.)
      EXE=$(find "$INSTALL_DIR" -maxdepth 1 -iname "*.exe" \
            -printf "%s %p\n" 2>/dev/null \
            | sort -rn | head -1 | cut -d" " -f2-)
    fi

    if [ -z "$EXE" ]; then
      systemd-cat -t game-install -p err echo "No .exe found: $GAME_NAME"
      exit 1
    fi
    systemd-cat -t game-install -p info echo "Executable: $EXE"

    # --- Step 5: Write Steam shortcut ---
    # Pass variables via env — avoids special-character issues with
    # embedding them inside a single-quoted heredoc.
    SHORTCUTS_FILE="$SHORTCUTS" \
    EXE_PATH="$EXE" \
    GAME_NAME_ENV="$GAME_NAME" \
    INSTALL_DIR_ENV="$INSTALL_DIR" \
    python3 <<'PYEOF'
    import vdf, binascii, ctypes, os, sys

    shortcuts_path = os.environ["SHORTCUTS_FILE"]
    exe_path       = os.environ["EXE_PATH"]
    game_name      = os.environ["GAME_NAME_ENV"]
    install_dir    = os.environ["INSTALL_DIR_ENV"]

    # AppID formula matching Steam's internal non-Steam game calculation.
    crc   = binascii.crc32(f'"{exe_path}"{game_name}'.encode("utf-8")) & 0xFFFFFFFF
    appid = ctypes.c_int32(crc | 0x80000000).value

    if os.path.exists(shortcuts_path):
        with open(shortcuts_path, "rb") as f:
            data = vdf.binary_loads(f.read())
    else:
        data = {"shortcuts": {}}

    shortcuts = data.get("shortcuts", {})

    # Idempotent: skip if already registered under this name
    for entry in shortcuts.values():
        if entry.get("AppName") == game_name:
            print("Already in Steam: " + game_name, file=sys.stderr)
            sys.exit(0)

    next_idx = str(max((int(k) for k in shortcuts.keys()), default=-1) + 1)
    shortcuts[next_idx] = {
        "appid":               appid,
        "AppName":             game_name,
        "Exe":                 exe_path,
        "StartDir":            install_dir,
        "icon":                "",
        "ShortcutPath":        "",
        "LaunchOptions":       "",
        "IsHidden":            0,
        "AllowDesktopConfig":  1,
        "AllowOverlay":        1,
        "OpenVR":              0,
        "Devkit":              0,
        "DevkitGameID":        "",
        "DevkitOverrideAppID": 0,
        "LastPlayTime":        0,
        "FlatpakAppID":        "",
        "tags":                {}
    }
    data["shortcuts"] = shortcuts

    os.makedirs(os.path.dirname(shortcuts_path), exist_ok=True)
    with open(shortcuts_path, "wb") as f:
        f.write(vdf.binary_dumps(data))

    print("Added to Steam: " + game_name + " (appid=" + str(appid) + ")")
    PYEOF

    # --- Step 6: Desktop notification ---
    notify-send "Game installed" "$GAME_NAME is ready in Steam Gaming Mode" \
      2>/dev/null || true

    systemd-cat -t game-install -p info echo "Done: $GAME_NAME"
  '';
}
