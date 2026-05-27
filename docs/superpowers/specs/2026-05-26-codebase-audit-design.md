# NixOS Config — Full Codebase Audit & Fix

**Date**: 2026-05-26
**Status**: Approved — ready for implementation plan
**Scope**: Full surgical audit + nuclear fix (code-complete for deferred features, no live activations)

---

## Context

Comprehensive audit of the `/etc/nixos` flake across all layers: system modules, home-manager
modules, overlays, packages, scripts, lib infrastructure, and documentation. Six parallel
agents surfaced issues across correctness, consistency, security, and completeness.

---

## Architecture

Three sequential waves. Each ends with a validation gate before the next starts.
No wave activates any currently-disabled service.

```
Wave 1 (no-risk)          Wave 2 (low-risk)         Wave 3 (deferred wiring)
─────────────────         ──────────────────        ─────────────────────────
docs, CLAUDE.md           code correctness          wazuh code-complete
stale comments            theme inheritance         protonvpn→sops upgrade
dead code removal         missing guards            ollama decision
spec status updates       overlay signatures        monitoring stubs
                          IPC path fix              monitor name centralised

→ flake check             → flake check             → dry-build
→ git commit              → dry-build               → git commit
                          → git commit
```

**Failure recovery**: each wave is independently reverted via `git revert`. No `nixos-rebuild
test` or `switch` is part of this plan — evaluation and build validation only.

---

## Wave 1 — No-risk (docs, comments, dead code)

| # | File | Change |
|---|------|--------|
| 1.1 | `CLAUDE.md` | Module list: add 13 missing modules (compartments, fan-control, kernel, hardware, nix-ld, nix, system, nvidia, media-server, monitoring, transcode, protonvpn-rotate, auditd) |
| 1.2 | `CLAUDE.md` | Sops pitfall: remove "not bootstrapped" claim — sops IS bootstrapped with real age key |
| 1.3 | `CLAUDE.md` | Ollama note: clarify module exists but is intentionally not loaded |
| 1.4 | `docs/superpowers/specs/2026-05-22-gaming-first-boot-design.md` | Status → "Implemented (2026-05-26)" |
| 1.5 | `docs/protonvpn-wg-setup.md` | Remove stale `cozy-singing-kurzweil.md` references (lines 154, 186) — replace with inline notes |
| 1.6 | `modules/hardening.nix:141-142` | Remove stale EROFS/flatpak caveat comment — flatpak is disabled |
| 1.7 | `modules/hardware.nix:2` | `_:` → `{ ... }:` for consistency |
| 1.8 | `modules/monitoring.nix:3` | `_:` → `{ ... }:` for consistency |
| 1.9 | `home/stoleyy/shell.nix:4` | Remove unused `inherit (theme) colors;` (colors not used in shell functions) |
| 1.10 | `scripts/detect-fan-hw.sh` | Fix SC2010: replace `ls \| grep -c` with glob count |
| 1.11 | `scripts/detect-fan-hw2.sh` | Fix SC2034: remove/use unused variables `linked`, `cdev_type`, `modalias` |

**Validation**: `nix flake check --no-build`

---

## Wave 2 — Low-risk (correctness fixes)

| # | File | Change |
|---|------|--------|
| 2.1 | `modules/update-routines.nix:116` | `User = "stoleyy"` → `User = host.user` (requires `host` in module args) |
| 2.2 | `modules/transcode.nix:75` | Add `users.groups.transcode = {};`, change `Group = "transcode"` |
| 2.3 | `modules/media-server.nix:34` | Move `vpnAddr` let-binding inside the `lib.mkIf cfg.enable` config block so it is only evaluated when media-server is enabled (and therefore protonvpn is expected to be present) |
| 2.4 | `modules/update-routines.nix:146` | `sleep 1` → `sleep 5` for graphical.target settle time |
| 2.5 | `home/stoleyy/browser.nix:19` | Add `inherit (theme) colors;`; replace `personal` domain hex with `colors.bg1`/`colors.bg2`; vault domain keeps intentional `#1B5E20` with comment "intentional: trust-zone green, not theme color" |
| 2.6 | `overlays/gamescope-wlserver-lock.nix:13` | Add explicit `final: prev:` function signature |
| 2.7 | `modules/gaming.nix:39` | Move IPC flag file `/tmp/gamemode-gpu-unlock` → `/run/gamemode-gpu-unlock` (tmpfs, correct lifetime for IPC) |
| 2.8 | `home/stoleyy/plasma.nix:81` | Add comment: `# spotify installed via modules/apps.nix` or remove if not installed |

**Validation**: `nix flake check --no-build` then `nixos-rebuild dry-build --flake .#predator`

---

## Wave 3 — Deferred wiring (code-complete, nothing activates)

| # | File | Change |
|---|------|--------|
| 3.1 | `modules/protonvpn.nix` | Replace `privateKeyFile = "/var/lib/protonvpn/privkey"` with `privateKeyFile = config.sops.secrets.protonvpn-private-key.path`; remove TODO comment; the secret is already declared in `hosts/predator/default.nix:108` |
| 3.2 | `lib/default.nix` | Add `./modules/ollama.nix` to module list (currently orphaned; it's a no-op `enable = false`) |
| 3.3 | `secrets/secrets.yaml` | Add `wazuh-indexer-password`, `wazuh-api-password`, `wazuh-dashboard-password` entries via `sops secrets/secrets.yaml` (interactive edit); set values to `CHANGEME` placeholder text. This requires running sops manually — note this in the impl plan as a user-run step. |
| 3.4 | `overlays/wazuh-agent.nix` | Add clear comment block explaining placeholder status + required derivation shape; or if a real wazuh package exists in nixpkgs, reference it |
| 3.5 | `modules/monitoring.nix` | Code-complete ntfy, beszel, vector config (correct service options, sops secret stubs for any tokens); leave `enable = false` on each with `# flip to enable` comments |
| 3.6 | `lib/host.nix` | Add `monitor = "DP-2";` field to centralise monitor name used across hyprland.nix, gaming.nix gamescope args |
| 3.7 | `home/stoleyy/hyprland.nix:592` | Replace hardcoded `--screen-root DP-2` with `--screen-root ${host.monitor}` |
| 3.8 | `hosts/predator/default.nix` | Update gamescope `--prefer-output DP-2` to use `host.monitor` |

**Validation**: `nixos-rebuild dry-build --flake .#predator`

---

## Out of scope

- `nixos-rebuild test` or `switch` — user runs these after reviewing commits
- Enabling wazuh-manager, monitoring, or other currently-disabled services live
- Hardware changes, BIOS settings, external infrastructure
- Fan control scripts cleanup (dead code, no module reference — low priority, informational)

---

## Issue Inventory (full audit findings)

### Critical (addressed in Wave 2)
- `home/stoleyy/browser.nix:19` — `colors` not inherited from theme; domain colors hardcoded hex

### Major (addressed in Wave 2–3)
- `modules/update-routines.nix:116` — `User = "stoleyy"` hardcoded instead of `host.user`
- `modules/media-server.nix:34` — unguarded `config.modules.protonvpn.clientAddress` access
- `modules/transcode.nix:75` — `Group = "users"` hardcoded instead of dedicated group
- `overlays/wazuh-agent.nix` — dead placeholder; wazuh-manager.nix references secrets absent from secrets.yaml
- `CLAUDE.md` — module list 13 modules short; sops pitfall claims "not bootstrapped" (wrong)
- `docs/2026-05-22-gaming-first-boot-design.md` — status "Pending" but fully implemented
- `docs/protonvpn-wg-setup.md` — stale references to non-existent plan file

### Minor (addressed in Waves 1–3)
- `modules/hardware.nix:2`, `modules/monitoring.nix:3` — `_:` style inconsistency
- `modules/hardening.nix:141-142` — stale EROFS/flatpak comment
- `modules/gaming.nix:39` — IPC flag file in `/tmp` (fragile)
- `modules/update-routines.nix:146` — `sleep 1` insufficient
- `home/stoleyy/shell.nix:4` — unused `inherit (theme) colors;`
- `home/stoleyy/plasma.nix:81` — Spotify hotkey without documented package source
- `overlays/gamescope-wlserver-lock.nix:13` — missing `final: prev:` signature
- `scripts/detect-fan-hw.sh` — SC2010 shellcheck warning
- `scripts/detect-fan-hw2.sh` — SC2034 unused variables
- `modules/ollama.nix` — exists but not imported in `lib/default.nix`
- `modules/protonvpn.nix` — TODO to use sops (now bootstrapped, do it)
- `lib/host.nix` — monitor name not centralised (duplicated across hyprland + gamescope)
