# Gaming-First Boot Architecture + Automated Game Pipeline

**Date:** 2026-05-22
**Status:** Pending implementation

---

## Goals

1. Hyprland becomes the default boot entry (primary daily driver).
2. `gaming-tuned` specialisation boots directly into Steam Gaming Mode via gamescope — no desktop, no compositor overhead.
3. Any FitGirl/DODI repack or pre-extracted game downloaded via qBittorrent automatically appears in Steam Gaming Mode after download completes.
4. **The only per-game manual step is adding the torrent to qBittorrent.**

---

## Hardware context

- RTX 4070 (Ada), proprietary driver (`open = false`), production package
- Samsung Odyssey OLED G80SD on HDMI-A-1: 3840x2160 @ 240 Hz, 10-bit, VRR
- Games library: `/home/stoleyy/games` (ext4, ~1.5 TiB, UUID-mounted)
- Data drive: `/data` (ext4, general storage)
- Native Steam has a known CEF crash (`error_code=1002`) in desktop mode — Steam runs via Flatpak (`com.valvesoftware.Steam`) for the Hyprland session

---

## Boot entries (systemd-boot)

| Entry | Session | Auto-login | Purpose |
|---|---|---|---|
| **Default** | `hyprland` | yes | Daily desktop: downloads, installs, work |
| `gaming-tuned` | `steam` (gamescope) | yes (mkForce) | Gaming only — no DE |
| `plasma` (new) | `plasma` (Wayland) | no | On-demand Plasma access |
| `debug` | unchanged | unchanged | Kernel diagnostics |

---

## Session facts (verified on-box)

- `programs.steam.gamescopeSession.enable = true` is already set in `modules/gaming.nix`.
- This registers `steam.desktop` in the SDDM session packages, confirmed present in the SDDM `SessionDir` at `/nix/store/…-desktops/share/wayland-sessions/steam.desktop`.
- The session exec is: `gamescope --steam -- steam -tenfoot -pipewire-dmabuf`
- `services.displayManager.defaultSession = "steam"` in a specialisation selects this session.
- Native Steam userdata: `~/.local/share/Steam/userdata/1789546687/` (Steam ID confirmed on-box).
- `shortcuts.vdf` does not yet exist — the script creates it fresh on first run.
- `python313Packages.vdf` (v3.4) is in nixpkgs and handles binary VDF via `vdf.binary_loads` / `vdf.binary_dumps`.

---

## Known risk: CEF crash in gamescope session

The native Steam binary has a confirmed CEF GPU process crash (`error_code=1002`) in desktop mode on this hardware. The gamescope session (`steam -tenfoot`) uses a different rendering path — gamescope owns KMS/Vulkan directly and does not use the same pressure-vessel GPU provider path that fails in desktop mode.

**This must be tested with `nixos-rebuild test` before committing to `switch`.** If Steam Gaming Mode fails to load, apply the fallback before proceeding:

Fallback: replace the session exec with a Flatpak wrapper. This requires a custom `steam-gamescope` package override in `modules/gaming.nix` that runs:
```bash
gamescope --steam -- flatpak run com.valvesoftware.Steam -tenfoot -pipewire-dmabuf
```

---

## Section 1: Default session change

**File:** `modules/desktop.nix`

Change `services.displayManager.defaultSession` from `"plasma"` to `"hyprland"`.

Plasma 6 remains installed (`services.desktopManager.plasma6.enable = true` stays). All KDE services and packages are kept — required for the `plasma` specialisation and harmless when Hyprland is the active session.

---

## Section 2: Specialisation restructure

**File:** `hosts/predator/default.nix`

### Remove

The `hyprland` specialisation. Hyprland is now the default; no specialisation is needed.

### Add: `plasma` specialisation

```nix
plasma.configuration = {
  services.displayManager.defaultSession = lib.mkForce "plasma";
  services.displayManager.autoLogin.enable = lib.mkForce false;
};
```

Boots to the SDDM greeter with no autologin. When the user decides to return to Plasma as their daily driver, `modules/desktop.nix` is updated and this specialisation is removed.

### Rewrite: `gaming-tuned` specialisation

```nix
gaming-tuned.configuration = {
  # Boot into Steam Gaming Mode via gamescope-session.
  services.displayManager.defaultSession = lib.mkForce "steam";
  services.displayManager.autoLogin = {
    enable = lib.mkForce true;
    user   = lib.mkForce "stoleyy";
  };

  # Gamescope display config for 4K @ 240 Hz OLED + HDR + VRR.
  # ENABLE_GAMESCOPE_WSI=1 is required for NVIDIA Vulkan WSI.
  # If --hdr-enabled causes a blank screen, remove it and retest.
  programs.steam.gamescopeSession = {
    args = [
      "--width"  "3840"
      "--height" "2160"
      "--refresh" "240"
      "--hdr-enabled"
      "--adaptive-sync"
    ];
    env = {
      ENABLE_GAMESCOPE_WSI = "1";
      DXVK_ASYNC = "1";
    };
  };

  # Disable PPD (pulled in by plasma6; conflicts with the explicit governor
  # service below).
  services.power-profiles-daemon.enable = lib.mkForce false;

  # Pin governor to performance.
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Override EPP to `performance` (base.nix sets balance_performance).
  # performance EPP + performance governor = maximum sustained clock.
  systemd.services.cpu-power-tuning.script = lib.mkForce ''
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      echo performance > "$f" || true
    done
    echo 1 > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost || true
  '';

  # Shed security overhead. This boot entry is used exclusively for
  # fullscreen gaming — no interactive network-facing exposure.
  security.auditd.enable   = lib.mkForce false;
  security.audit.enable    = lib.mkForce false;
  security.apparmor.enable = lib.mkForce false;

  # Kernel performance params. Appended to the base list; Linux last-param-wins
  # means init_on_alloc=0 here overrides hardening.nix's init_on_alloc=1.
  boot.kernelParams = [
    "mitigations=off"
    "nowatchdog"
    "init_on_alloc=0"
    "init_on_free=0"
    "skew_tick=1"
    "pcie_aspm=off"
    "threadirqs"
  ];
};
```

### Keep unchanged

`debug` specialisation — no changes.

---

## Section 3: Automation pipeline

### 3.1 qBittorrent

**File:** `home/stoleyy/default.nix` — add `pkgs.qbittorrent` to `home.packages`.

qBittorrent has no home-manager module. The completion hook is configured **once** in the GUI (not per-game):

```
qBittorrent → Preferences → Downloads
→ "Run external program on torrent completion"
→ game-install "%F" "%N"
```

`%F` = absolute save path of the download, `%N` = torrent display name.

The qBittorrent config file (`~/.config/qBittorrent/qBittorrent.conf`) is intentionally not managed by Nix — managing it declaratively would silently overwrite GUI changes on every rebuild.

**Download directory:** Set to any staging location (e.g., `/data/downloads`). The `game-install` script receives the exact path via `%F` so the location does not affect the pipeline.

### 3.2 `game-install` script

**File:** `modules/gaming.nix` — added to `environment.systemPackages` as a `pkgs.writeShellScriptBin "game-install"` derivation.

The script is a Nix derivation (not a plain `writeShellScriptBin`) so that `python3.withPackages (p: [ p.vdf ])` and its other runtime dependencies can be wired into its PATH via `makeWrapper`.

Runtime dependencies (all already in the system or added here):
- `wine` — from `wineWowPackages.stable` (already in `environment.systemPackages`)
- `python3.withPackages (p: [ p.vdf ])` — binary VDF manipulation
- `rsync`, `findutils`, `coreutils` — standard, always available
- `libnotify` — for the `notify-send` completion notification in Hyprland

#### Full logic

```
Inputs:
  $1 = SAVE_PATH      absolute path to the torrent's downloaded files
  $2 = TORRENT_NAME   torrent display name from qBittorrent

Constants:
  GAMES_DIR  = /home/stoleyy/games
  STEAM_ID   = auto-detected: first subdirectory of ~/.local/share/Steam/userdata/
  SHORTCUTS  = ~/.local/share/Steam/userdata/$STEAM_ID/config/shortcuts.vdf

Step 1 — Sanitize game name
  Strip from TORRENT_NAME (case-insensitive, left to right):
    Scene/repack group tags: FitGirl, DODI, EMPRESS, CPY, CODEX, SKIDROW,
                             RELOADED, GOG, MULTI\d+, REPACK
    Version patterns:        v\d+[\.\d]*, \[\d+[\.\d]*\], Build\.\d+,
                             Early.Access, EA
    Edition tags:            Deluxe.Edition, Gold.Edition, GOTY, Complete.Edition,
                             Ultimate.Edition, Directors.Cut
    File/size tags:          \(\d+bit\), \(x64\), \(x86\)
  Replace remaining dots, underscores, hyphens with spaces.
  Collapse multiple spaces. Strip leading/trailing whitespace.
  Result: GAME_NAME

Step 2 — Detect install type
  Find setup.exe or Setup.exe within depth 2 of SAVE_PATH.
  If found  → REPACK  (run Windows installer via Wine)
  If absent → PRE_EXTRACTED (move directory as-is)

Step 3a — Repack install
  INSTALL_DIR = $GAMES_DIR/$GAME_NAME
  Run: wine "$SETUP_EXE" /SILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS \
           /DIR="$INSTALL_DIR"
  Wait: poll every 5 s until all wine/wineserver processes for this user exit.
        Hard timeout: 30 minutes. On timeout → log error to journal and exit 1.

Step 3b — Pre-extracted
  INSTALL_DIR = $GAMES_DIR/$GAME_NAME
  rsync -a --remove-source-files "$SAVE_PATH/" "$INSTALL_DIR/"

Step 4 — Find main executable
  Priority:
    1. $INSTALL_DIR/$GAME_NAME.exe         (exact name match)
    2. $INSTALL_DIR/game.exe               (common convention)
    3. $INSTALL_DIR/launch.exe             (common launcher name)
    4. Largest .exe directly in $INSTALL_DIR (non-recursive — avoids picking
       redistributable installers inside _CommonRedist/, DirectX/, vcredist/)
  If no .exe found → log error to journal and exit 1.

Step 5 — Write Steam shortcut (see Section 3.3)

Step 6 — Notify
  notify-send "Game installed" "$GAME_NAME is ready in Steam Gaming Mode"
  (No-op if no notification daemon is running, e.g. during background installs
  while the session is not active.)
```

#### Wine wait implementation

```bash
wine "$SETUP_EXE" /SILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS \
     /DIR="$INSTALL_DIR" &
ELAPSED=0
while pgrep -u "$USER" -x wine >/dev/null 2>&1 \
   || pgrep -u "$USER" -x wineserver >/dev/null 2>&1; do
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  [ $ELAPSED -ge 1800 ] && {
    systemd-cat -t game-install -p err \
      echo "Installer timeout for: $GAME_NAME"
    exit 1
  }
done
```

### 3.3 shortcuts.vdf writer

Implemented as an inline `python3 -c` call within `game-install`.

Steam computes a non-Steam game's AppID as:
```python
import binascii, ctypes
crc = binascii.crc32((exe_path + game_name).encode("utf-8")) & 0xFFFFFFFF
appid = ctypes.c_int32(crc | 0x80000000).value  # signed int32
```
Using this exact formula ensures the AppID matches what Steam generates internally, so any artwork added later (via SteamGridDB or Steam itself) associates to the correct shortcut.

Shortcut entry written to `shortcuts.vdf`:
```python
{
  str(next_index): {
    "appid":               appid,        # signed int32
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
}
```

If `shortcuts.vdf` does not exist, the script creates it with the standard `"shortcuts"` root key in binary VDF format.

### 3.4 SteamGridDB artwork (optional / stretch goal)

Not required for the game to appear and be playable. If `STEAMGRIDDB_API_KEY` is present in the environment (wired via `home.sessionVariables`):

1. Query `https://www.steamgriddb.com/api/v2/search/autocomplete/<game_name>`
2. Fetch the first result's grid image, hero image, and logo
3. Save to `~/.local/share/Steam/userdata/$STEAM_ID/config/grid/` named by AppID

The script skips this block silently if the key is absent.

---

## Section 4: Files changed

| File | Change |
|---|---|
| `modules/desktop.nix` | `defaultSession = "hyprland"` |
| `hosts/predator/default.nix` | Remove `hyprland` spec; add `plasma` spec; rewrite `gaming-tuned` |
| `modules/gaming.nix` | Add `game-install` derivation to `environment.systemPackages` |
| `home/stoleyy/default.nix` | Add `pkgs.qbittorrent` to `home.packages` |

**Files NOT changed:**
- `home/stoleyy/plasma.nix` — stays imported; KDE config files are harmless under Hyprland
- `modules/hyprland.nix` — no changes needed
- `modules/hardening.nix` — no changes; gaming-tuned's `init_on_alloc=0` overrides via kernel last-param-wins
- All other modules — unchanged

---

## Section 5: Achievements

| Game type | Behaviour |
|---|---|
| Steam (native library) | Full Steam achievements with cloud sync |
| Pirated — crack includes Goldberg/CODEX emulator | Local achievements tracked automatically in `~/.steam/steam/userdata/*/` — no config needed; no cloud sync |
| Pirated — no emulator bundled | `pkgs.goldberg-emu` (v0.2.5, in nixpkgs) can be added to `environment.systemPackages` and deployed per-game if desired |

---

## Section 6: Edge cases

| Scenario | Handling |
|---|---|
| Non-InnoSetup packer (rare DODI/EMPRESS variants) | Silent flags may be ignored; Wine launches the GUI installer. User completes it manually. The rest of the pipeline (exe detection, shortcut write) runs normally afterward. |
| Multiple .exe at root | Priority heuristic picks most likely (Section 3.2). Wrong pick can be corrected in Steam's shortcut properties. |
| Repack extracts to a subdirectory (`SAVE_PATH/GameName-FitGirl/setup.exe`) | Depth-2 search finds the setup.exe correctly. |
| Steam running when shortcut is added | Steam must restart to pick it up. Script sends `notify-send` prompting the user to restart Steam. In gamescope session, shortcut appears on next Steam launch. |
| `/home/stoleyy/games` not mounted | Script checks for directory existence at startup and exits with a journal error if the games volume is absent. |
| Multiple Steam accounts (multiple userdata dirs) | Auto-detection takes the first directory. Acceptable for a single-user box. |

---

## Section 7: Validation plan

Order is mandatory. Never skip ahead.

```
1.  nix flake check --no-build
    Catches eval errors in the specialisation rewrite and new script derivation.

2.  nixos-rebuild dry-build --flake .#predator
    Full eval + closure plan without activation.

3.  sudo nixos-rebuild test --flake .#predator
    Activates without touching the bootloader. Verify on this boot:
      a. Default session is now hyprland (check /etc/sddm.conf DefaultSession=hyprland.desktop)
      b. Hyprland autologin works
      c. game-install binary is on PATH

4.  Reboot — select gaming-tuned from systemd-boot menu.
    CRITICAL: verify Steam Gaming Mode loads without CEF crash.
      - If it loads: step 5.
      - If it fails (black screen, crash): apply CEF fallback (Section above),
        rebuild test, retest before continuing.

5.  Reboot back to default (Hyprland).
    Add a small test torrent via qBittorrent.
    Confirm game-install fires on completion and shortcut appears in
    ~/.local/share/Steam/userdata/1789546687/config/shortcuts.vdf.

6.  systemctl --failed && journalctl -p err -b 0
    Confirm clean.

7.  sudo nixos-rebuild switch --flake .#predator
    Only after steps 4-6 pass.

8.  git commit && git push
```
