# Greenlight Xbox Streaming — NixOS Integration Design

**Date:** 2026-05-27
**Status:** Approved

## Goal

Add Greenlight (open-source Xbox xCloud/Remote Play client) to the NixOS config so it is launchable from:
- Hyprland session via rofi (desktop app)
- Steam Gaming Mode (gamescope session) via non-Steam shortcut

Scope: LAN streaming only. Bluetooth Xbox controller. No remote/Tailscale setup.

## Constraints

- Greenlight is **not in nixpkgs** (25.11 or unstable)
- Flatpak is **disabled** (`services.flatpak.enable = false`)
- All apps are nix-managed — no manual downloads
- System: NixOS 25.11, Hyprland/Wayland, NVIDIA RTX 4070

## Architecture

Two file changes only:

```
packages/greenlight.nix   (new)
modules/gaming.nix        (add package + env var)
```

One post-rebuild manual step: add Greenlight as a Non-Steam Game in Steam UI once.

## Components

### 1. `packages/greenlight.nix`

Uses `pkgs.appimageTools.wrapType2` — the nixpkgs-canonical pattern for AppImage
packaging (same approach used for obsidian pre-nixpkgs).

```
pkgs.appimageTools.wrapType2 {
  name = "greenlight";
  version = "<pinned>";
  src = pkgs.fetchurl {
    url = "https://github.com/unknownskl/greenlight/releases/download/v<ver>/Greenlight-<ver>.AppImage";
    hash = "sha256-<prefetched>";
  };
}
```

`wrapType2` responsibilities:
- Creates FHS sandbox so AppImage finds system libs
- Produces `$out/bin/greenlight`
- Extracts `.desktop` file from AppImage and installs it → rofi sees Greenlight immediately

Pre-rebuild step: `nix-prefetch-url <AppImage URL>` to get the hash.

### 2. `modules/gaming.nix`

Two additions:

**Package:**
```nix
(pkgs.callPackage ../packages/greenlight.nix { })
```
added to `environment.systemPackages` — same pattern as `gameInstall`.

**Wayland env var:**
```nix
environment.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT = "auto";
```
Tells Electron to use Ozone/Wayland rendering. Applies globally (beneficial for all
Electron apps). No conflict with Brave (which already passes `--ozone-platform-hint=auto`
via CLI flags).

### 3. Steam Gaming Mode shortcut (manual, one-time)

After rebuild, in the default Hyprland session:

1. Open Steam
2. Library → "Add a Game" → "Add a Non-Steam Game..."
3. Greenlight appears in the list (Steam scans `.desktop` files)
4. Add it — entry persists in `shortcuts.vdf`, visible in gamescope Big Picture mode

Not declarative by design: `shortcuts.vdf` is binary VDF owned and mutated by Steam.
Writing it from `home.activation` risks clobbering Steam's own changes.

### 4. Bluetooth Xbox Controller

No config changes needed. Already configured in `modules/hardware.nix`:

- `hardware.bluetooth.enable = true`
- `powerOnBoot = true`
- `ClassicBondedOnly = false` (required for Xbox BT pairing)
- `hardware.steam-hardware.enable = true` (Xbox udev rules)

Pair via `bluetoothctl` or Bluetooth settings UI. Works OOTB.

## Data Flow

```
Xbox (Instant-On + Remote Features enabled)
  ↕ LAN (local network)
Greenlight AppImage (FHS-wrapped nix derivation)
  ↕ input
Xbox Bluetooth controller (paired to PC via BlueZ)
```

## Xbox Console Setup (out-of-scope for nix config)

Required one-time on the console:
- Settings → General → Power options → **Instant-On**
- Settings → Devices & connections → Remote features → **Enable remote features**
- Console signed into Microsoft account (same as Greenlight login)
- Wired Ethernet recommended but Wi-Fi works

## Updating Greenlight

On a new upstream release:
1. Get new AppImage URL from GitHub releases
2. `nix-prefetch-url <url>` → new hash
3. Update `url` + `hash` in `packages/greenlight.nix`
4. Rebuild

## Out of Scope

- Remote streaming (outside home network / Tailscale)
- xpadneo / xone kernel drivers (not needed for Bluetooth)
- Controller rebinding / in-app config
