# stoleyy/nixos-config

NixOS 25.11 flake for a single Acer Predator desktop (`predator`), single-OS
(migrated off a former Windows dual-boot). **Active flake on the running system
is `/etc/nixos`, not this clone.**

## Hardware

- Intel i7-13700K, 64 GB RAM
- NVIDIA RTX 4070 (Ada) — uses the `open` kernel module + `production` driver
- Samsung Odyssey OLED G80SD on **HDMI-A-1** at 3840x2160@240Hz, 10-bit
  (XBGR2101010), VRR active
- Root: `/dev/nvme0n1p4` ext4, ~294 GB (grown from 47.8 GB via GParted Live)
- Games library: ext4 at `/home/stoleyy/games`, ~1.5 TiB (formerly an NTFS
  partition; reformatted in the post-Windows migration, flake-declared by-UUID)
- `/data`: ext4 (former Windows NVMe — wiped + reformatted, flake-declared)

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

- **Plasma 6 X11** (`plasmax11`) is the deliberate SDDM default
  (`services.displayManager.defaultSession = "plasmax11"`, SDDM greeter on
  Xorg — `modules/desktop.nix`). The Plasma **Wayland** session crash-loops
  on this RTX 4070 + open kernel module (login → ~1 s flash → SDDM); it was
  reverted X11 in `59af7a7` (NOT the stale state CLAUDE.md once claimed for
  `76d8d69`). A Wayland fix is in progress (`nvidia-drm.fbdev=1` in
  `modules/nvidia.nix`); X11 stays default until an on-box
  `nixos-rebuild test` proves the Wayland session stays up.
- **Plasma Wayland** is still installed and selectable from the SDDM
  session dropdown to retest after driver bumps.
- **Hyprland** is selectable from the SDDM dropdown and via its boot
  specialisation entry.
- Both home-manager profiles ship simultaneously; HM imports both stacks.

## Rebuilding

```
cd /etc/nixos
sudo git pull origin main
sudo nixos-rebuild switch --flake .#predator
```

After a big rebuild, free disk: `sudo nh clean all`. If `/nix/store` truly
fills: `sudo nix-collect-garbage -d`.

## Workflow loop

`.vscode/tasks.json` encodes the pipeline below as labeled one-click steps.
Each task gets a dedicated terminal panel addressable as `@terminal:<label>`
in the Claude Code extension — reference live output rather than pasting
snapshots that go stale within one fix.

`.mcp.json` registers `mcp-nixos` so option paths get validated against the
live `search.nixos.org` for the active release instead of hallucinated from
training data.

`.claude/hooks/bootstrap-nix.sh` installs Nix on session start in Claude
Code on the Web containers so the `nix develop` harness (nixfmt, statix,
deadnix, …) is runnable from chat. First session in a fresh container
pays ~30-90 s; subsequent sessions are near-instant. Devshell pre-warm is
off by default — set `NIX_BOOTSTRAP_PREWARM=1` to realize the closure
during bootstrap (+60-180 s, but the first `nix develop -c <tool>` is
then instant).

**When something fails, identify the class before proposing a fix:**

| Class | Signal | First read |
|---|---|---|
| Eval | error before `building '...'` | `nix flake check --no-build` traceback |
| Build | `builder for '/nix/store/…drv' failed` | `nix log /nix/store/…drv` |
| Activation | `Failed to start <unit>` during `switch-to-configuration` | `journalctl -xeu <unit>` |
| Runtime | unit "running" but misbehaves | `journalctl -u <unit> -b 0` |

Hypothesis-first debugging on NixOS confirms whatever you point at — the
option surface is large enough that plausible-looking fixes are everywhere.
Read the specific log first, then propose.

**Validation pipeline (in order, never skip ahead):**

1. `nix flake check --no-build` — eval-time validation
2. `nixos-rebuild dry-build --flake .#predator` — full eval, no closure realization
3. `sudo nixos-rebuild test --flake .#predator` — activates, not bootable
4. `systemctl --failed` and `journalctl -p err -b 0` — verify clean
5. `sudo nixos-rebuild switch --flake .#predator` — only if step 4 is clean
6. `git commit && git push` — keep git generation in lockstep with NixOS

`test` is reversible by reboot; `switch` is not. Going straight to `switch`
is the most common cause of stuck or unbootable generations.

For changes whose effect is not yet understood, use the extension's plan
mode so the proposed diff is visible before anything writes. Use the
checkpoint/rewind UI on a message when a fix goes sideways — combined with
git generations that's two layers of rollback.

## Local validation tools

`nix develop` drops into a shell with everything below pre-built:

```
nix flake check                   # eval-time validation (add --no-build for fast path)
nixos-rebuild build --flake .#predator   # full closure realization, no activation
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
- **Intentional mounts live in `hosts/predator/default.nix`, never
  hand-added to `hardware-configuration.nix`** — the latter is *mostly*
  `nixos-generate-config` output (one deliberate exception: the
  load-bearing `vmd` line — see next pitfall); a regen silently drops
  hand-added `fileSystems` entries (`/data` would simply stop mounting).
  The games and `/data` mounts are declared once, in `default.nix`,
  **by UUID**: the device node was historically self-contradictory
  (`nvme0n1p2` vs `nvme1n1p2` across files/commits) — trust the UUID +
  on-box `blkid`, never the node.
- **`boot.initrd.kernelModules = [ "vmd" ]` in
  `hardware-configuration.nix` is LOAD-BEARING — never remove it or move
  it to `availableKernelModules`.** Intel VMD is disabled in BIOS but the
  controller persists; the kernel still needs the `vmd` driver to find the
  root NVMe by-UUID, force-loaded so it inits before Stage-1 root discovery
  (6.12+). Removing it = unbootable "cannot find root" (PR #8 tried → #13
  bricked → #14 is the current fix). A fresh `nixos-generate-config`
  clobbers this placement — re-apply it after any regen.
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
- **SDDM remembers the per-user last session and overrides
  `services.displayManager.defaultSession`** — the system default only
  applies to a user with no stored session. Changing `defaultSession`
  (Plasma↔Hyprland, X11↔Wayland) looks like it "didn't apply" because SDDM
  prefers the remembered session in `~/.local/share/sddm/state.conf`. Clear
  that file (or pick the target session once from the SDDM dropdown) for the
  new default to take effect.
