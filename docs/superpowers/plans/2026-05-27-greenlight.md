# Greenlight Xbox Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Greenlight (Xbox Remote Play client) as a declarative nix package, launchable from Hyprland (rofi) and Steam Gaming Mode.

**Architecture:** `appimageTools.wrapType2` wraps the upstream AppImage into an FHS sandbox, producing a proper binary + `.desktop` file. Two files change: new `packages/greenlight.nix`, edited `modules/gaming.nix`. Post-rebuild: pair Xbox controller over Bluetooth and add Greenlight as a Non-Steam Game in Steam UI once.

**Tech Stack:** Nix `appimageTools.wrapType2`, `fetchurl`, nixfmt, nixos-rebuild validation pipeline.

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `packages/greenlight.nix` | `wrapType2` derivation — fetches AppImage, produces binary + `.desktop` |
| Modify | `modules/gaming.nix` | Add package to systemPackages + `ELECTRON_OZONE_PLATFORM_HINT` session var |

---

### Task 1: Get Greenlight AppImage URL and hash

**Files:** none (prep step)

- [ ] **Step 1: Find the latest AppImage release URL**

  Open in browser: `https://github.com/unknownskl/greenlight/releases/latest`

  Under "Assets", find the file ending in `.AppImage` (x86_64 Linux build).
  Copy the full URL — it will look like:
  `https://github.com/unknownskl/greenlight/releases/download/vX.X.X/Greenlight-X.X.X.AppImage`

  Note the version number (e.g. `3.2.0`) — you'll need it in Task 2.

- [ ] **Step 2: Prefetch the SHA256 hash**

  ```bash
  VERSION=X.X.X   # replace with actual version
  URL="https://github.com/unknownskl/greenlight/releases/download/v${VERSION}/Greenlight-${VERSION}.AppImage"
  nix-prefetch-url --type sha256 "${URL}" 2>/dev/null | xargs nix hash to-sri --type sha256
  ```

  Expected output: a string beginning with `sha256-` followed by base64.
  Example: `sha256-abc123...=`

  Save this string — it goes into `packages/greenlight.nix` as the `hash` value.

---

### Task 2: Write `packages/greenlight.nix`

**Files:**
- Create: `packages/greenlight.nix`

- [ ] **Step 1: Create the derivation file**

  Create `/etc/nixos/packages/greenlight.nix` with this content (substitute your
  actual VERSION and HASH from Task 1):

  ```nix
  { pkgs }:
  pkgs.appimageTools.wrapType2 {
    name = "greenlight";
    version = "X.X.X";
    src = pkgs.fetchurl {
      url = "https://github.com/unknownskl/greenlight/releases/download/vX.X.X/Greenlight-X.X.X.AppImage";
      hash = "sha256-YOUR_HASH_HERE";
    };
  }
  ```

  `wrapType2` automatically:
  - Builds an FHS sandbox around the AppImage
  - Extracts and installs the `.desktop` file + icon from inside the AppImage
  - Produces `$out/bin/greenlight`

- [ ] **Step 2: Format with nixfmt**

  ```bash
  cd /etc/nixos
  nix develop -c nixfmt packages/greenlight.nix
  ```

  Expected: no output (formats in place, exits 0).

- [ ] **Step 3: Git-track the new file**

  ```bash
  git add packages/greenlight.nix
  ```

  `nixos-rebuild` excludes untracked files from eval — must `git add` before rebuilding.

---

### Task 3: Integrate into `modules/gaming.nix`

**Files:**
- Modify: `modules/gaming.nix` (lines 116–122 — the `environment.systemPackages` block)

- [ ] **Step 1: Add Greenlight to systemPackages**

  In `modules/gaming.nix`, the `environment.systemPackages` block currently reads:

  ```nix
  environment.systemPackages = with pkgs; [
    gameInstall
    mangohud
    prismlauncher
    adwsteamgtk
  ];
  ```

  Change it to:

  ```nix
  environment.systemPackages = with pkgs; [
    gameInstall
    mangohud
    prismlauncher
    adwsteamgtk
    (callPackage ../packages/greenlight.nix { })
  ];
  ```

- [ ] **Step 2: Add the Wayland Electron env var**

  Add this line directly after the `environment.systemPackages` block (before the closing `}`):

  ```nix
  environment.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT = "auto";
  ```

  This tells all Electron apps (Greenlight included) to use Ozone/Wayland rendering.
  It does not conflict with Brave's `--ozone-platform-hint=auto` CLI flag — both say the same thing.

- [ ] **Step 3: Format with nixfmt**

  ```bash
  cd /etc/nixos
  nix develop -c nixfmt modules/gaming.nix
  ```

  Expected: no output, exits 0.

---

### Task 4: Validate pipeline

Follow the project's required validation order. **Never skip to switch.**

- [ ] **Step 1: Eval check**

  ```bash
  cd /etc/nixos
  nix flake check --no-build
  ```

  Expected: exits 0, no errors.
  If `error:` appears before any `building '...'`, it is an eval error — fix the nix syntax before proceeding.

- [ ] **Step 2: Dry build (full eval, no realisation)**

  ```bash
  nixos-rebuild dry-build --flake .#predator
  ```

  Expected: resolves the closure, prints the path that would be built, exits 0.
  If `builder for '/nix/store/...drv' failed`, run `nix log /nix/store/...drv` to read the build log.

- [ ] **Step 3: Test activation (reversible)**

  ```bash
  sudo nixos-rebuild test --flake .#predator
  ```

  Expected: activates the new generation without making it the boot default.
  If a unit fails during activation, `journalctl -xeu <unit>` reveals the cause.

- [ ] **Step 4: Verify clean**

  ```bash
  systemctl --failed
  journalctl -p err -b 0 | tail -30
  ```

  Expected: `systemctl --failed` shows 0 units. `journalctl` output should not contain
  new errors introduced by this change.

- [ ] **Step 5: Verify Greenlight binary exists**

  ```bash
  which greenlight
  greenlight --version 2>/dev/null || echo "no --version flag (ok for Electron apps)"
  ```

  Expected: `which greenlight` prints a path under `/run/current-system/sw/bin/greenlight`.

- [ ] **Step 6: Switch (make bootable)**

  Only run this if Step 4 is clean:

  ```bash
  sudo nixos-rebuild switch --flake .#predator
  ```

  Expected: exits 0, new generation is the boot default.

---

### Task 5: Commit

**Files:** `packages/greenlight.nix`, `modules/gaming.nix`

- [ ] **Step 1: Stage and commit**

  ```bash
  cd /etc/nixos
  git add packages/greenlight.nix modules/gaming.nix
  git commit -m "feat(apps): add greenlight xbox streaming client

  - packages/greenlight.nix: appimageTools.wrapType2 wrapping upstream AppImage
  - modules/gaming.nix: add to systemPackages + ELECTRON_OZONE_PLATFORM_HINT=auto"
  ```

- [ ] **Step 2: Push**

  ```bash
  git push origin main
  ```

---

### Task 6: Post-rebuild setup (manual, one-time)

This task requires a running Hyprland session — do it after `nixos-rebuild switch`.

- [ ] **Step 1: Pair Xbox controller via Bluetooth**

  Open Bluetooth settings (or run `bluetoothctl` in a terminal):

  ```bash
  bluetoothctl
  # Inside bluetoothctl:
  power on
  agent on
  scan on
  # Press the sync button on the Xbox controller until it flashes rapidly
  # The controller appears as "Xbox Wireless Controller"
  pair <MAC_ADDRESS>
  connect <MAC_ADDRESS>
  trust <MAC_ADDRESS>
  ```

  After pairing, the controller auto-connects on future boots.
  Verify: `cat /proc/bus/input/devices | grep -A4 Xbox` should show the gamepad.

- [ ] **Step 2: Verify Greenlight appears in rofi**

  Press the rofi keybind (Super+D or your configured binding). Type "greenlight".
  Expected: Greenlight appears as a launchable app.

- [ ] **Step 3: Add Greenlight as a Non-Steam Game**

  Open Steam (in the Hyprland session):
  1. Library → "Add a Game" (bottom-left) → "Add a Non-Steam Game..."
  2. In the list, find "Greenlight" (Steam scans `.desktop` files from XDG data dirs)
  3. Check the box next to Greenlight → "Add Selected Programs"

  This writes an entry to `~/.steam/steam/userdata/<id>/config/shortcuts.vdf`.
  The entry persists and is visible in the gamescope Gaming Mode session automatically.

- [ ] **Step 4: First connection test (LAN)**

  Launch Greenlight from rofi:
  - Sign in with your Microsoft account (same account on the Xbox)
  - Your Xbox should appear in the device list
  - Click Connect — the console wakes from Instant-On and begins streaming

  If the console does not appear: verify on the Xbox that Settings → Devices & connections
  → Remote features → "Enable remote features" is checked and the network test passed.

---

## Troubleshooting

**Greenlight not in rofi after rebuild:**
- `ls $(dirname $(which greenlight))/../share/applications/` — check if `.desktop` file is there
- If missing, `wrapType2` may have failed to extract it from the AppImage; check the build log: `nix build --impure --expr '(import <nixpkgs> {}).callPackage /etc/nixos/packages/greenlight.nix {}' 2>&1`

**Black screen / no rendering in Greenlight:**
- `ELECTRON_OZONE_PLATFORM_HINT=auto greenlight` — run from terminal to see stderr
- If Chromium says it can't find a display: ensure you're in the Hyprland session (Wayland), not a bare TTY

**Xbox controller not connecting:**
- Check `bluetoothctl devices` — is the controller listed as trusted?
- Run `journalctl -u bluetooth -b 0` for BlueZ errors

**Xbox not appearing in Greenlight device list:**
- Confirm Xbox power mode is Instant-On (not Sleep)
- Confirm "Enable remote features" is toggled on in Xbox settings
- PC and Xbox must be on the same subnet (same router, same VLAN)
