# Gaming-First Boot Architecture + Automated Game Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Hyprland the default boot, rewrite gaming-tuned to boot into Steam Gaming Mode via gamescope, and automate the full FitGirl/DODI → Steam library pipeline so the only per-game manual step is adding a torrent to qBittorrent.

**Architecture:** Four targeted file edits — default session change in `modules/desktop.nix`, specialisation restructure in `hosts/predator/default.nix`, `game-install` script added to `modules/gaming.nix` as a `writeShellApplication` derivation, and `qbittorrent` added to home packages. No new files needed.

**Tech Stack:** NixOS 25.11, SDDM, gamescope (`programs.steam.gamescopeSession`), Wine (`wineWowPackages.stable`), Python `vdf` 3.4 (binary VDF read/write), qBittorrent 5.1.4

---

## File map

| File | Change |
|---|---|
| `modules/desktop.nix` | `defaultSession = "hyprland"` (one line) |
| `hosts/predator/default.nix` | Remove `hyprland` spec; add `plasma` spec; rewrite `gaming-tuned` spec |
| `modules/gaming.nix` | Add `let gameInstall = ...` block + `gameInstall` to `environment.systemPackages` |
| `home/stoleyy/default.nix` | Add `pkgs.qbittorrent` to `home.packages` |

---

## Task 1: Make Hyprland the default session

**Files:**
- Modify: `modules/desktop.nix:18`

- [ ] **Step 1: Edit `modules/desktop.nix`**

  Change line 18 from:
  ```nix
  services.displayManager.defaultSession = "plasma";
  ```
  To:
  ```nix
  services.displayManager.defaultSession = "hyprland";
  ```

- [ ] **Step 2: Eval check**

  ```bash
  cd /etc/nixos
  nix flake check --no-build
  ```
  Expected: exits 0, no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add modules/desktop.nix
  git commit -m "feat: make hyprland the default boot session"
  ```

---

## Task 2: Restructure specialisations

**Files:**
- Modify: `hosts/predator/default.nix:160-216`

The entire `specialisation = { ... };` block (lines 160–216) is replaced. The `hyprland` spec is removed (Hyprland is now the default), a `plasma` spec is added for on-demand Plasma access, and `gaming-tuned` is rewritten to boot into the gamescope Steam session with full performance and security overhead disabled.

- [ ] **Step 1: Replace the specialisation block**

  Find the block starting with `specialisation = {` at line 160 and replace the entire block through the closing `};` at line 216 with:

  ```nix
    specialisation = {
      # On-demand Plasma boot — boots to the SDDM greeter (no autologin) so
      # the session can be chosen from the dropdown. When the user returns to
      # Plasma as their daily driver, flip defaultSession in modules/desktop.nix
      # and remove this specialisation.
      plasma.configuration = {
        services.displayManager.defaultSession = lib.mkForce "plasma";
        services.displayManager.autoLogin.enable = lib.mkForce false;
      };

      # Verbose boot + tracing tools for diagnosing kernel/driver issues.
      # Select "debug" from the systemd-boot menu.
      # nomodeset disables KMS/DRM so Stage 1 errors print to the plain VGA
      # console instead of being swallowed by the NVIDIA framebuffer.
      debug.configuration = {
        boot.kernelParams = [
          "loglevel=7"
          "debug"
          "nomodeset"
        ];
        environment.systemPackages = with pkgs; [
          strace
          ltrace
          gdb
        ];
      };

      # Pure gaming boot — autologins into Steam Gaming Mode via gamescope.
      # Used exclusively for fullscreen gaming; boots straight to the Steam
      # library with no desktop, compositor, or security-monitoring overhead.
      # Session name "steam" is registered by programs.steam.gamescopeSession
      # (modules/gaming.nix) and confirmed present in the SDDM SessionDir.
      gaming-tuned.configuration = {
        # Boot into Steam Gaming Mode via gamescope-session.
        services.displayManager.defaultSession = lib.mkForce "steam";
        services.displayManager.autoLogin = {
          enable = lib.mkForce true;
          user   = lib.mkForce "stoleyy";
        };

        # Gamescope display config: 4K @ 240 Hz OLED + HDR + VRR.
        # ENABLE_GAMESCOPE_WSI=1 is required for NVIDIA Vulkan WSI.
        # If --hdr-enabled causes a blank screen on first boot, remove it
        # and rebuild. DXVK_ASYNC=1 enables async shader compilation.
        programs.steam.gamescopeSession = {
          args = [
            "--width"        "3840"
            "--height"       "2160"
            "--refresh"      "240"
            "--hdr-enabled"
            "--adaptive-sync"
          ];
          env = {
            ENABLE_GAMESCOPE_WSI = "1";
            DXVK_ASYNC          = "1";
          };
        };

        # Disable PPD — pulled in by plasma6, conflicts with the explicit
        # governor service below. Without this, both fight over sysfs writes.
        services.power-profiles-daemon.enable = lib.mkForce false;

        # Pin governor to performance for the entire gaming session.
        powerManagement.cpuFreqGovernor = lib.mkForce "performance";

        # Override EPP from base.nix's balance_performance to performance.
        # performance EPP + performance governor = maximum sustained boost.
        systemd.services.cpu-power-tuning.script = lib.mkForce ''
          for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo performance > "$f" || true
          done
          echo 1 > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost || true
        '';

        # Shed security monitoring overhead. This boot entry is exclusively
        # used for fullscreen gaming — no network-facing interactive services.
        security.auditd.enable   = lib.mkForce false;
        security.audit.enable    = lib.mkForce false;
        security.apparmor.enable = lib.mkForce false;

        # Performance kernel params. Appended to the base list; Linux
        # last-param-wins means init_on_alloc=0 overrides hardening.nix's =1.
        boot.kernelParams = [
          "mitigations=off"
          "nowatchdog"
          # Remove page-zeroing overhead. ~1-7% CPU savings in
          # allocation-heavy games. Last-param-wins overrides hardening.nix.
          "init_on_alloc=0"
          "init_on_free=0"
          # Reduce timer interrupt lock contention across cores.
          "skew_tick=1"
          # Eliminate PCIe ASPM link transition latency.
          # Increases idle power draw — acceptable for a dedicated gaming boot.
          "pcie_aspm=off"
          # Make hard IRQs preemptible — lowers worst-case interrupt latency.
          "threadirqs"
        ];
      };
    };
  ```

- [ ] **Step 2: Eval check**

  ```bash
  nix flake check --no-build
  ```
  Expected: exits 0.

- [ ] **Step 3: Full eval without build**

  ```bash
  nixos-rebuild dry-build --flake .#predator 2>&1 | tail -5
  ```
  Expected: ends with `Done.` or similar, no eval errors. This takes 30–90 s.

- [ ] **Step 4: Commit**

  ```bash
  git add hosts/predator/default.nix
  git commit -m "feat: restructure specialisations — hyprland default, gaming-tuned gamescope session"
  ```

---

## Task 3: Add `game-install` script

**Files:**
- Modify: `modules/gaming.nix:1` (add `let` block), `modules/gaming.nix:88` (add to `systemPackages`)

`pkgs.writeShellApplication` is used because it accepts `runtimeInputs` that get prepended to PATH inside the script — this ensures all deps are available regardless of how qBittorrent's subprocess inherits the environment.

`writeShellApplication` automatically adds `#!/usr/bin/env bash` and enables `errexit`, `nounset`, `pipefail`. Do not add these manually in `text`.

`writeShellApplication` also runs `shellcheck` on the script during build. The script must pass shellcheck. The Python heredoc (`<<'PYEOF'`) is not linted by shellcheck (it only lints bash-typed heredocs).

- [ ] **Step 1: Add the `let` block and `gameInstall` derivation**

  Replace the first line of `modules/gaming.nix`:
  ```nix
  { pkgs, ... }:
  ```
  With:
  ```nix
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
        procps    # pgrep
        systemd   # systemd-cat
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

          ELAPSED=0
          while pgrep -u "$USER" -x wine    >/dev/null 2>&1 \
             || pgrep -u "$USER" -x wineserver >/dev/null 2>&1; do
            sleep 5
            ELAPSED=$((ELAPSED + 5))
            if [ "$ELAPSED" -ge 1800 ]; then
              systemd-cat -t game-install -p err echo "Installer timeout: $GAME_NAME"
              exit 1
            fi
          done
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
        crc   = binascii.crc32((exe_path + game_name).encode("utf-8")) & 0xFFFFFFFF
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
  ```

- [ ] **Step 2: Add `gameInstall` to `environment.systemPackages`**

  In the same file, find:
  ```nix
    environment.systemPackages = with pkgs; [
      mangohud
  ```
  Replace with:
  ```nix
    environment.systemPackages = with pkgs; [
      gameInstall
      mangohud
  ```

- [ ] **Step 3: Eval check (catches shellcheck failures in the script)**

  ```bash
  nix flake check --no-build
  ```
  Expected: exits 0. If shellcheck fails, the error will name the offending line in `text`.

  Common fix if shellcheck complains about the `find -printf` pattern:
  ```nix
  # add to writeShellApplication:
  excludeShellChecks = [ "SC2012" ];
  ```
  Add this as a sibling of `runtimeInputs` and `text`.

- [ ] **Step 4: Build the derivation in isolation to confirm it compiles**

  ```bash
  nix build --impure --expr \
    '(import (builtins.getFlake "/etc/nixos").inputs.nixpkgs {}).writeShellApplication {
       name = "game-install-test";
       runtimeInputs = [];
       text = "echo ok";
     }'
  ```
  Expected: builds cleanly. (This just verifies the infrastructure; the real build happens in step 5.)

- [ ] **Step 5: Full dry-build to confirm the whole closure evaluates**

  ```bash
  nixos-rebuild dry-build --flake .#predator 2>&1 | tail -5
  ```
  Expected: no errors.

- [ ] **Step 6: Commit**

  ```bash
  git add modules/gaming.nix
  git commit -m "feat: add game-install script — qBittorrent → Steam pipeline"
  ```

---

## Task 4: Add qBittorrent to home packages

**Files:**
- Modify: `home/stoleyy/default.nix:34-41`

- [ ] **Step 1: Add `pkgs.qbittorrent` to `home.packages`**

  Find in `home/stoleyy/default.nix`:
  ```nix
      packages = with pkgs; [
        keepassxc
  ```
  Replace with:
  ```nix
      packages = with pkgs; [
        qbittorrent
        keepassxc
  ```

- [ ] **Step 2: Eval check**

  ```bash
  nix flake check --no-build
  ```
  Expected: exits 0.

- [ ] **Step 3: Commit**

  ```bash
  git add home/stoleyy/default.nix
  git commit -m "feat: add qbittorrent for game download pipeline"
  ```

---

## Task 5: Activate and test on live system

- [ ] **Step 1: Full dry-build (final pre-flight)**

  ```bash
  nixos-rebuild dry-build --flake .#predator 2>&1 | tail -10
  ```
  Expected: completes without errors.

- [ ] **Step 2: Activate with `test` (no bootloader write)**

  ```bash
  sudo nixos-rebuild test --flake .#predator
  ```
  Expected: completes. Then:

- [ ] **Step 3: Verify session config on current boot**

  ```bash
  grep -E "DefaultSession|Session=" /etc/sddm.conf
  ```
  Expected output:
  ```
  Session=hyprland.desktop
  DefaultSession=hyprland.desktop
  ```

- [ ] **Step 4: Verify `game-install` is on PATH**

  ```bash
  which game-install
  game-install --help 2>&1 | head -3 || true
  ```
  Expected: path under `/run/current-system/sw/bin/game-install`.

- [ ] **Step 5: Smoke-test the VDF shortcut writer**

  ```bash
  mkdir -p /tmp/game-test/FakeGame
  printf 'MZ' > /tmp/game-test/FakeGame/FakeGame.exe
  game-install /tmp/game-test/FakeGame "FakeGame-FitGirl"
  ```
  Expected:
  - `journalctl -t game-install -n 10` shows "Processing: FakeGame" and "Done: FakeGame"
  - File `~/.local/share/Steam/userdata/1789546687/config/shortcuts.vdf` is created
  - Python check: `python3 -c "import vdf; f=open('$HOME/.local/share/Steam/userdata/1789546687/config/shortcuts.vdf','rb'); d=vdf.binary_loads(f.read()); print(d)"`
    shows the FakeGame entry with correct AppName and Exe fields

- [ ] **Step 6: Clean up test data**

  ```bash
  rm -rf /tmp/game-test
  # Remove FakeGame shortcut by editing shortcuts.vdf or just leaving it —
  # Steam will ignore a non-existent exe path.
  ```

- [ ] **Step 7: Reboot into gaming-tuned to test the gamescope session**

  Select `gaming-tuned` from the systemd-boot menu.

  **CRITICAL CHECKPOINT — CEF crash test:**
  - SDDM should autologin directly into the gamescope session
  - Steam Gaming Mode (`-tenfoot` UI) should load within ~15 s
  - If Steam loads: proceed to Step 8
  - If Steam fails (black screen, or journal shows `error_code=1002`):
    - Boot back to default
    - Apply the CEF fallback from the spec (custom steam-gamescope wrapper using Flatpak Steam)
    - Rebuild test and retest before continuing

- [ ] **Step 8: Verify gaming-tuned performance settings**

  While booted into gaming-tuned:
  ```bash
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
  cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
  systemctl is-active auditd    # expected: inactive
  systemctl is-active apparmor  # expected: inactive
  ```
  Expected: governor = `performance`, EPP = `performance`, auditd and apparmor inactive.

- [ ] **Step 9: Reboot back to default (Hyprland)**

- [ ] **Step 10: Check for failures**

  ```bash
  systemctl --failed
  journalctl -p err -b 0 | grep -v "NVIDIA\|nvidia" | head -20
  ```
  Expected: no failed units, no unexpected errors.

---

## Task 6: Wire up qBittorrent completion hook (one-time manual step)

This task is performed in the GUI — not per-game, just once after first launch.

- [ ] **Step 1: Launch qBittorrent**

  From Hyprland: open qBittorrent (it is now in `home.packages`).

- [ ] **Step 2: Set the completion hook**

  ```
  qBittorrent → Tools → Preferences → Downloads
  → Enable "Run external program on torrent completion"
  → Set command to: game-install "%F" "%N"
  → Click OK
  ```

  `%F` = absolute save path of the completed torrent files
  `%N` = torrent display name (used for game name sanitization)

- [ ] **Step 3: Set the default save path**

  In the same Preferences → Downloads panel:
  ```
  Default Save Path: /data/downloads
  ```
  (Or any staging directory — `game-install` receives the exact path via `%F` and moves files to `/home/stoleyy/games/`.)

- [ ] **Step 4: End-to-end pipeline test**

  Download a small, legally free game or any torrent to verify the pipeline fires:
  - Add a torrent in qBittorrent
  - After completion, check `journalctl -t game-install -f` for the processing log
  - Verify the game appears in `~/.local/share/Steam/userdata/1789546687/config/shortcuts.vdf`
  - Boot gaming-tuned — the game should appear in the Steam library under "Non-Steam Games" or the shortcuts section

---

## Task 7: Switch and push

Only run this task after Task 5 Step 10 is clean and the gaming-tuned session loaded Steam successfully.

- [ ] **Step 1: Write the bootloader entry**

  ```bash
  sudo nixos-rebuild switch --flake .#predator
  ```
  Expected: completes. The default boot entry is now Hyprland. gaming-tuned, plasma, and debug appear in the systemd-boot menu.

- [ ] **Step 2: Final health check**

  ```bash
  systemctl --failed
  journalctl -p err -b 0 | grep -v "NVIDIA\|nvidia" | head -20
  ```
  Expected: clean.

- [ ] **Step 3: Push**

  ```bash
  git push
  ```

---

## Appendix A: CEF fallback (apply only if gaming-tuned fails in Task 5 Step 7)

If Steam Gaming Mode crashes with `error_code=1002` in the gamescope session, the native Steam binary has the same CEF GPU issue in `-tenfoot` mode that it has in desktop mode.

**Fix:** Override the session binary to use Flatpak Steam instead. In `modules/gaming.nix`, add a second let-binding after `gameInstall`:

```nix
  steamGamescopeWrapper = pkgs.writeShellScriptBin "steam-gamescope-flatpak" ''
    exec gamescope --steam -- \
      flatpak run com.valvesoftware.Steam -tenfoot -pipewire-dmabuf "$@"
  '';
```

And in `gaming-tuned.configuration`:

```nix
  programs.steam.gamescopeSession.args = [
    # keep existing args...
  ];
  # Override the session binary:
  environment.systemPackages = [ steamGamescopeWrapper ];
  # Then update the SDDM session desktop file to use the new binary.
  # This requires a custom session package — see nixpkgs writeTextDir pattern
  # from modules/gaming.nix in the spec. File a follow-up task for this.
```

Note: Replacing the session binary properly requires generating a custom `steam.desktop` session file via `services.displayManager.sessionPackages`. This is a follow-up task if the fallback is needed.

---

## Appendix B: Achievements for pirated games

Most FitGirl/DODI cracks bundle a Goldberg or CODEX Steam API emulator already. Local achievements are stored in `~/.steam/steam/userdata/*/` automatically — no config required.

If a specific game's crack does not include an emulator, `pkgs.goldberg-emu` (v0.2.5) is in nixpkgs. Add it to `environment.systemPackages` and follow the per-game setup at the goldberg-emu repo for that title.
