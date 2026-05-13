# stoleyy/nixos-config

NixOS 25.11 flake for a single Acer Predator desktop (`predator`). Dual-boot
with Windows on a separate NVMe drive. **Active flake on the running system is
`/etc/nixos`, not this clone.**

## Hardware

- Intel i7-13700K, 64 GB RAM
- NVIDIA RTX 4070 (Ada) — uses the `open` kernel module + `production` driver
- Samsung Odyssey OLED G80SD on **HDMI-A-1** at 3840x2160@240Hz, 10-bit
  (XBGR2101010), VRR active
- Root: `/dev/nvme0n1p4` ext4, ~294 GB (grown from 47.8 GB via GParted Live)
- Games NTFS partition: `/dev/nvme0n1p2`, ~1.5 TiB
- Windows on `/dev/nvme1n1`

## Repo layout

- `flake.nix` — inputs (nixpkgs 25.11, home-manager 25.11, nix-gaming,
  nixos-hardware, plasma-manager, spicetify-nix) + the single host entry
  `nixosConfigurations.predator` + a `nix develop` shell
- `lib/default.nix` — `mkHost` factory; **the canonical list of system modules
  lives here, not in `flake.nix`**
- `hosts/predator/` — per-host hardware config
  (`hardware-configuration.nix`, `default.nix`)
- `modules/*.nix` — system modules (base, networking, desktop, audio, fonts,
  gaming, apps, hardening, hyprland, theming)
- `home/stoleyy/*.nix` — home-manager modules; `home/stoleyy/default.nix`
  imports them all
- `overlays/` — auto-imported via `overlays/default.nix` (any `*.nix` dropped
  in becomes an overlay; a non-`.nix` file aborts evaluation by design)

## Sessions

- **Plasma 6 Wayland** is the SDDM default
  (`services.displayManager.defaultSession = "plasma"` in
  `modules/desktop.nix`, set in commit `76d8d69`).
- **Hyprland** is the fallback, selectable from the SDDM dropdown.
- Both home-manager profiles ship simultaneously; HM imports both stacks.

## Rebuilding

```
cd /etc/nixos
sudo git pull origin main
sudo nixos-rebuild switch --flake .#predator
```

After a big rebuild, free disk: `sudo nh clean all`. If `/nix/store` truly
fills: `sudo nix-collect-garbage -d`.

Dry-build (full eval + closure realization, no switch):

```
nixos-rebuild build --flake /etc/nixos#predator
```

## Local validation (no system change)

```
nix develop                       # drops into shell with nixd/statix/deadnix/etc.
nix flake check                   # eval-time validation
nixos-rebuild build --flake .#predator   # full build, no switch
nixfmt --check **/*.nix
statix check .
deadnix .
gitleaks detect --no-banner --no-git
shellcheck .claude/hooks/*.sh
```

## Runtime introspection (after a successful switch)

- `kreadconfig6 --file kdeglobals --group General --key ColorScheme`
- `qdbus org.kde.plasmashell /PlasmaShell evaluateScript '<js>'` (Plasma)
- `hyprctl monitors all` (Hyprland session)
- `kscreen-doctor -o` (Plasma session)
- `vulnix -S` — CVE scan against the live closure
- `nix path-info -Sh /run/current-system` — closure size
- `nvd diff /run/booted-system /run/current-system` — generation diff

## Conventions

- Every module is a `{ pkgs, ... }: { ... }` function. `inputs` is forwarded
  via `specialArgs`; `lib` available as `pkgs.lib` or as a normal arg.
- System modules are listed in `lib/default.nix`'s `modules = [ ... ]`. **Do
  not list them again in `flake.nix`.**
- Home-manager imports go in `home/stoleyy/default.nix` only.
- `home-manager.backupFileExtension = "backup"` is enabled (see Pitfalls).
- Format every `.nix` file with `nixfmt` before committing.

## Pitfalls (learned the hard way)

- **HM `.backup` orphan collisions** block rebuild. If a previous HM run
  failed mid-flight and left `~/.gtkrc-2.0.backup` (or any other `*.backup`),
  the next rebuild fails because HM refuses to clobber existing `.backup`
  files. Fix: `rm` the offending `.backup` files and re-run.
- **HM 25.11 git option rename**: settings live under `programs.git.settings`
  (not `userName` / `extraConfig` from older versions).
- **`services.pulseaudio.enable = false`** — renamed from
  `hardware.pulseaudio.enable` in 25.11.
- **`nixos-rebuild` excludes untracked files**: after `nixos-generate-config`
  produces `hosts/predator/hardware-configuration.nix`, `git add` it before
  rebuilding or eval can't see it.
- **Hyprland 0.46+** removed `gestures.workspace_swipe*` and
  `render.explicit_sync`; both must be absent from
  `home/stoleyy/hyprland.nix`.
- **`rofi-wayland` merged into `rofi`** in nixpkgs 25.11 — use `pkgs.rofi`,
  not `pkgs.rofi-wayland`.
- **`services.thermald` errors on this hardware** — leave off.
- **Plasma-manager widget keys are camelCase** (`iconTasks`, `systemTray`,
  `digitalClock`), not lowercase. Plain string widgets like
  `"org.kde.plasma.marginsseparator"` work as bare list entries.
- **`pkgs.kdePackages.qttools` provides `qdbus`** (no `6` suffix), despite
  upstream KDE docs writing `qdbus6`.
- **`pkgs.layan-kde` was removed** from nixpkgs (Plasma-5-only). Use built-in
  `org.kde.breezedark.desktop` + a custom color scheme override.
- **Plasma-manager `nightLight.mode`** has an `apply` that capitalizes the
  string, so `"times"` becomes `"Times"`. The `"Times"` mode requires
  `time.morning` and `time.evening`. Easiest: use `mode = "automatic"`.
- **HM `gtk` module owns `~/.config/gtk-{3,4}.0/gtk.css`** — use
  `gtk.gtk3.extraCss` / `gtk.gtk4.extraCss`, never `home.file` for those paths.
