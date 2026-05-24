{ pkgs, ... }:

let
  gameInstall = pkgs.writeShellApplication {
    name = "game-install";

    runtimeInputs = with pkgs; [
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
      GAMES_DIR="/home/stoleyy/games"
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
  };
in

{
  programs = {
    gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 0; # ananicy owns nice (was 10; would fight ananicy)
          ioprio = "off"; # ananicy owns ionice ("off" disables; 0 = highest!)
          inhibit_screensaver = 1;
          # Full boost while a game runs. No defaultgov on purpose → GameMode
          # restores the PRE-game governor, which is correctly "powersave" in
          # the secure default boot and "performance" in the gaming-tuned
          # specialisation. (softrealtime omitted — SCHED_ISO is a no-op on
          # mainline/nixpkgs 6.12; the -ck patch was never upstreamed.)
          desiredgov = "performance";
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          # card1 = NVIDIA RTX 4070; card0 = simpledrm (no vendor file).
          # Without this, GameMode tries card0 and logs:
          # "Couldn't open vendor file at /sys/class/drm/card0/device/vendor"
          device = 1;
          nv_powermizer_mode = 1; # force NVIDIA powermizer to max-perf while gaming
        };
      };
    };

    gamescope = {
      enable = true;
      # Grant CAP_SYS_NICE so gamescope can renice its threads for realtime
      # scheduling. Without this, the gaming-tuned greetd session logs
      # "No CAP_SYS_NICE, falling back to regular-priority compute and threads."
      capSysNice = true;
    };

    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      gamescopeSession.enable = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
      # Vetted nix-gaming SteamOS sysctl bundle: vm.max_map_count=2147483642
      # (fixes CS2/Hogwarts/DayZ/UE5 Proton crashes — default 65530 too low),
      # kernel.split_lock_mitigate=0, sched_cfs_bandwidth_slice_us,
      # tcp_fin_timeout. Module imported in lib/default.nix.
      platformOptimizations.enable = true;
    };
  };

  # System-wide auto nice/ionice/sched/oom tuning for ALL apps (browser,
  # compiles, media) via the CachyOS rule set. GameMode cedes renice/ioprio
  # (above) so they don't fight; GameMode keeps the governor swap + GPU power
  # state. cgroup_load uses BPF — ananicy-cpp runs as root (systemd service),
  # so kernel.unprivileged_bpf_disabled=1 (hardening.nix) does NOT block it;
  # only unprivileged BPF is restricted. Set false if the journal ever shows
  # BPF/cgroup errors from ananicy.
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
    settings = {
      check_freq = 5;
      cgroup_load = true;
      apply_nice = true;
      apply_ioclass = true;
      apply_ionice = true;
      apply_sched = true;
      apply_oom_score_adj = true;
    };
  };

  # Suppress Wine's verbose debug logging — measurable overhead for zero
  # diagnostic value during normal gameplay. Arch Wiki gaming page standard.
  environment.sessionVariables.WINEDEBUG = "-all";

  environment.systemPackages = with pkgs; [
    gameInstall
    mangohud
    heroic
    lutris
    prismlauncher
    adwsteamgtk
  ];
}
