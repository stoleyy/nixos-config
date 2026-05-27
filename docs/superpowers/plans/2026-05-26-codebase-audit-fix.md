# Codebase Audit Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply all findings from the nuclear codebase audit — 3 waves of fixes from docs/stale-code through correctness/safety to deferred feature wiring.

**Architecture:** Three sequential waves (no-risk → low-risk → deferred wiring), each validated before the next starts. No `nixos-rebuild test` or `switch` — evaluation and build validation only.

**Tech Stack:** NixOS 25.11 flake, home-manager 25.11, sops-nix, WireGuard, systemd, bash

---

## File Structure

**Wave 1 — modified:**
- `CLAUDE.md` — module list, sops pitfall, ollama note
- `docs/superpowers/specs/2026-05-22-gaming-first-boot-design.md` — status update
- `docs/protonvpn-wg-setup.md` — remove stale plan references (lines 154, 186)
- `modules/hardening.nix` — remove stale EROFS/flatpak comment (lines 141–142)
- `modules/hardware.nix` — signature `_:` → `{ ... }:`
- `modules/monitoring.nix` — signature `_:` → `{ ... }:`
- `home/stoleyy/shell.nix` — remove unused `inherit (theme) colors;`
- `scripts/detect-fan-hw.sh` — SC2010: `ls | grep -c` → `find`
- `scripts/detect-fan-hw2.sh` — SC2034: remove unused variables

**Wave 2 — modified:**
- `modules/update-routines.nix` — add `host` arg, `User = host.user`, `sleep 5`
- `modules/transcode.nix` — add `users.groups.transcode`, use it
- `modules/media-server.nix` — add protonvpn dependency assertion
- `home/stoleyy/browser.nix` — inherit colors, personal domain → theme refs
- `overlays/gamescope-wlserver-lock.nix` — `_: prev:` → `final: prev:`
- `lib/host.nix` — `gamemodeFlagFile` → `/run/gamemode/gpu-unlock`
- `modules/gaming.nix` — add tmpfiles rule for `/run/gamemode`
- `home/stoleyy/plasma.nix` — remove spotify hotkey (package not installed)

**Wave 3 — modified:**
- `modules/protonvpn.nix` — clean up stale TODO text in option description
- `hosts/predator/default.nix` — add `restartUnits` to protonvpn sops secret
- `lib/default.nix` — add `modules/ollama.nix` + add `host` to extraSpecialArgs
- `modules/monitoring.nix` — signature → `{ pkgs, config, ... }:`, uncomment ntfy-failure template
- `lib/host.nix` — add `monitor = "DP-2";` field
- `home/stoleyy/hyprland.nix` — add `host` arg, use `host.monitor` in wallpaper engine
- `hosts/predator/default.nix` — use `host.monitor` in gamescope `--prefer-output`

---

## Wave 1 — No-risk (docs, comments, dead code)

### Task 1: Update CLAUDE.md module list, sops pitfall, and ollama note

**Files:**
- Modify: `CLAUDE.md:27-30` (module list)
- Modify: `CLAUDE.md:276-281` (sops pitfall)

- [ ] **Step 1: Fix module list (lines 27–30)**

Replace:
```
- `modules/*.nix` — system modules (base, networking, desktop, audio, fonts,
  gaming, apps, hardening, hyprland, theming, ollama, containers, wazuh-agent,
  protonvpn, auditd, update-routines). `wazuh-manager.nix` exists but is
  commented out in `lib/default.nix` pending cert bootstrap.
```
With:
```
- `modules/*.nix` — system modules. Active (imported in `lib/default.nix`): base, nix,
  nix-ld, system, kernel, hardware, fan-control, nvidia, networking, desktop, hyprland,
  audio, fonts, theming, apps, gaming, compartments, hardening, auditd, wazuh-agent,
  protonvpn, protonvpn-rotate, containers, media-server, monitoring, transcode,
  update-routines. Not imported: `ollama.nix` (disable-only stub), `wazuh-manager.nix`
  (disabled — pending cert bootstrap).
```

- [ ] **Step 2: Replace stale sops pitfall (lines 276–281)**

Replace:
```
- **sops-nix age key not bootstrapped** — `.sops.yaml` still has the
  placeholder `age1REPLACE_WITH_OUTPUT_OF_SSH_TO_AGE`. Until the real host
  key is generated (`ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`) and
  `sops updatekeys secrets/secrets.yaml` is run, all `sops.secrets.*`
  references will fail at activation. Do not add sops secret references to
  modules until bootstrapped.
```
With:
```
- **sops-nix is fully bootstrapped** — real age key in `.sops.yaml`, two
  secrets encrypted in `secrets/secrets.yaml` (`protonvpn-private-key`,
  `github-pat`), both actively used via `sops.secrets.*` in
  `hosts/predator/default.nix`. To add a new secret: run
  `sops secrets/secrets.yaml`, add the key, then declare it in
  `hosts/predator/default.nix`.
```

- [ ] **Step 3: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors (CLAUDE.md is not evaluated by Nix).

---

### Task 2: Update stale doc status and remove dead plan references

**Files:**
- Modify: `docs/superpowers/specs/2026-05-22-gaming-first-boot-design.md:4`
- Modify: `docs/protonvpn-wg-setup.md:154` and `docs/protonvpn-wg-setup.md:186`

- [ ] **Step 1: Mark gaming spec as implemented**

In `docs/superpowers/specs/2026-05-22-gaming-first-boot-design.md`, replace line 4:
```
**Status:** Pending implementation
```
With:
```
**Status:** Implemented (2026-05-26)
```

- [ ] **Step 2: Fix protonvpn-wg-setup.md line 154**

Replace:
```
Once sops-nix is wired up (Tier 2.1 in the optimization roadmap):
```
With:
```
sops-nix is now bootstrapped. The private key is in `secrets/secrets.yaml`
and wired via `hosts/predator/default.nix`. To re-encrypt or rotate the key:
```

- [ ] **Step 3: Fix protonvpn-wg-setup.md line 186**

Replace:
```
- Tier 2.1 in `/home/stoleyy/.claude/plans/cozy-singing-kurzweil.md` — sops-nix upgrade path
```
With:
```
- sops-nix upgrade is complete — private key is in `secrets/secrets.yaml`
```

---

### Task 3: Fix module signatures (`_:` → `{ ... }:`)

**Files:**
- Modify: `modules/hardware.nix:2`
- Modify: `modules/monitoring.nix:3`

- [ ] **Step 1: Fix hardware.nix**

In `modules/hardware.nix`, line 1–2 currently reads:
```
# Physical hardware: CPU microcode, Bluetooth, Logitech, zram swap.
_:
```
Replace `_:` with `{ ... }:`:
```
# Physical hardware: CPU microcode, Bluetooth, Logitech, zram swap.
{ ... }:
```

- [ ] **Step 2: Fix monitoring.nix**

In `modules/monitoring.nix`, line 1–3 currently reads:
```
# Self-monitoring: ntfy notifications on failure, beszel metrics hub, gatus service probes, vector log pipeline.
# All services currently disabled — flip enables back when a remote sink or dashboard is set up.
_:
```
Replace `_:` with `{ ... }:`:
```
# Self-monitoring: ntfy notifications on failure, beszel metrics hub, gatus service probes, vector log pipeline.
# All services currently disabled — flip enables back when a remote sink or dashboard is set up.
{ ... }:
```

- [ ] **Step 3: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### ~~Task 4: shell.nix inherit~~ — REMOVED (false finding)

`home/stoleyy/shell.nix:4` — `inherit (theme) colors;` was flagged as unused by the audit agent
but `colors` IS used at lines 146–147 (starship palette `fg` and `bg` values).
No change needed. shell.nix is clean.

---

### Task 5: Fix shellcheck warnings in fan scripts

**Files:**
- Modify: `scripts/detect-fan-hw.sh:68-70`
- Modify: `scripts/detect-fan-hw2.sh:48-49,74`

- [ ] **Step 1: Fix detect-fan-hw.sh SC2010**

Lines 68–70 currently:
```bash
  fans=$(ls "$d" 2>/dev/null | grep -c "^fan" || true)
  pwms=$(ls "$d" 2>/dev/null | grep -c "^pwm" || true)
```
Replace with (use `find` instead of `ls | grep`):
```bash
  fans=$(find "$d" -maxdepth 1 -name 'fan[0-9]*' 2>/dev/null | wc -l)
  pwms=$(find "$d" -maxdepth 1 -name 'pwm[0-9]*' 2>/dev/null | wc -l)
```

- [ ] **Step 2: Fix detect-fan-hw2.sh SC2034 — remove unused variables**

Line 48: remove `linked=$(readlink -f "${cdev}type" 2>/dev/null || true)` — variable never read.

Line 49: remove `cdev_type=$(cat "${cdev}type" 2>/dev/null || echo "?")` — variable never read.

Line 74: remove `modalias=$(cat "${wmi}modalias" 2>/dev/null || echo "?")` — variable never read.

(Simply delete those three assignment lines.)

- [ ] **Step 3: Remove stale flatpak EROFS comment from hardening.nix (lines 141–142)**

In `modules/hardening.nix`, find and remove these two lines:
```nix
      # erofs intentionally NOT blacklisted — Flatpak's freedesktop runtime 23.08+
      # uses EROFS for image layers; blacklisting breaks Flatpak updates.
```
(flatpak is disabled — `services.flatpak.enable = false` in apps.nix — making this caveat obsolete)

- [ ] **Step 4: Validate Wave 1 and commit**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -30
```
Expected: clean (no errors).

```bash
git add -p  # stage only the Wave 1 files
git commit -m "$(cat <<'EOF'
chore: wave 1 — docs, stale comments, dead code cleanup

- CLAUDE.md: complete module list, fix sops pitfall (bootstrapped),
  ollama clarification
- gaming-first-boot spec: mark implemented
- protonvpn docs: remove stale plan file references
- hardware.nix, monitoring.nix: _: → { ... }:
- shell.nix: remove unused inherit (theme) colors
- hardening.nix: remove obsolete EROFS/flatpak comment
- detect-fan-hw*.sh: fix SC2010, SC2034 shellcheck warnings

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Wave 2 — Low-risk (correctness fixes)

### Task 6: Fix hardcoded username and sleep in update-routines.nix

**Files:**
- Modify: `modules/update-routines.nix:2,116,146`

- [ ] **Step 1: Add `host` to module args**

Line 2 currently:
```nix
{ config, pkgs, ... }:
```
Change to:
```nix
{ config, pkgs, host, ... }:
```

- [ ] **Step 2: Replace hardcoded username**

Line 116 currently:
```nix
          User = "stoleyy";
```
Replace with:
```nix
          User = host.user;
```

- [ ] **Step 3: Increase settle time**

Line 146 currently:
```nix
          sleep 1 # brief settle; graphical.target ordering handles most deps
```
Replace with:
```nix
          sleep 5 # brief settle; graphical.target ordering handles most deps
```

- [ ] **Step 4: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### Task 7: Dedicated `transcode` group in transcode.nix

**Files:**
- Modify: `modules/transcode.nix:75` + add group declaration

- [ ] **Step 1: Declare the group**

In `modules/transcode.nix`, find the closing `}` of the top-level attrset and add before it (or alongside any existing `users.*` declarations):
```nix
  users.groups.transcode = { };
```
If there is no existing `users.*` block, add it as a new top-level key in the module output.

- [ ] **Step 2: Change the service Group**

Line 75 currently:
```nix
      Group = "users";
```
Replace with:
```nix
      Group = "transcode";
```

- [ ] **Step 3: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### Task 8: Add protonvpn dependency assertion to media-server.nix

**Files:**
- Modify: `modules/media-server.nix` — add assertions block

- [ ] **Step 1: Add assertion**

In `modules/media-server.nix`, inside the top-level `{ ... }` attrset (after the closing `in`), add an `assertions` list. Find a suitable place (e.g., after the `users` block) and add:

```nix
  assertions = [
    {
      assertion = config.modules.protonvpn.enable;
      message = ''
        modules/media-server: qBittorrent binds to the ProtonVPN WireGuard
        interface (InterfaceAddress = ${vpnAddr}). Set
          modules.protonvpn.enable = true
        in hosts/predator/default.nix, or remove the InterfaceAddress binding
        from the qBittorrent config in media-server.nix.
      '';
    }
  ];
```

- [ ] **Step 2: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors (assertion is checked at activation, not eval).

---

### Task 9: Fix browser.nix color inheritance

**Files:**
- Modify: `home/stoleyy/browser.nix:19,32-33`

- [ ] **Step 1: Add `colors` to the inherit**

Line 19 currently:
```nix
  inherit (theme) hexToRgb;
```
Replace with:
```nix
  inherit (theme) hexToRgb colors;
```

- [ ] **Step 2: Replace hardcoded personal domain colors with theme references**

Lines 31–36 currently:
```nix
    personal = {
      color = "#07062F"; # Sanctuary indigo (matches existing theme)
      frame = "#0A094E";
      label = "Personal";
      description = "Daily browsing, YouTube, social media";
      dataDir = "Brave-Browser"; # default Brave profile
    };
```
Replace with:
```nix
    personal = {
      color = colors.bg1; # Sanctuary indigo — primary bg
      frame = colors.bg2; # Slightly lighter indigo for frame
      label = "Personal";
      description = "Daily browsing, YouTube, social media";
      dataDir = "Brave-Browser"; # default Brave profile
    };
```

- [ ] **Step 3: Add comment to vault/untrusted/disposable domains**

For `vault`, `untrusted`, and `disposable` domains, add a comment explaining the intentional non-theme colors:
```nix
    vault = {
      color = "#1B5E20"; # intentional: trust-zone green (not Sanctuary palette)
      frame = "#2E7D32"; # intentional: lighter trust-zone green for frame
      ...
    };
    untrusted = {
      color = "#B71C1C"; # intentional: danger red (not Sanctuary palette)
      frame = "#C62828"; # intentional: danger red frame
      ...
    };
    disposable = {
      color = "#E65100"; # intentional: warning orange (not Sanctuary palette)
      frame = "#F57C00"; # intentional: warning orange frame
      ...
    };
```

- [ ] **Step 4: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### Task 10: Fix gamescope overlay function signature

**Files:**
- Modify: `overlays/gamescope-wlserver-lock.nix:13`

- [ ] **Step 1: Add explicit `final:` parameter**

Line 13 currently:
```nix
_: prev: {
```
Replace with:
```nix
final: prev: {
```
(The overlay doesn't use `final` but the function signature convention requires both args to be named.)

- [ ] **Step 2: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### Task 11: Move GameMode IPC flag file from /tmp to /run

**Files:**
- Modify: `lib/host.nix:10`
- Modify: `modules/gaming.nix` — add tmpfiles rule

- [ ] **Step 1: Update the path in lib/host.nix**

Line 10 currently:
```nix
  gamemodeFlagFile = "/tmp/gamemode-gpu-unlock";
```
Replace with:
```nix
  # IPC flag: GameMode touches this to signal nvidia-undervolt to unlock clocks.
  # /run/gamemode/ is a tmpfs dir created at boot (see modules/gaming.nix tmpfiles rule).
  gamemodeFlagFile = "/run/gamemode/gpu-unlock";
```

- [ ] **Step 2: Add tmpfiles rule in gaming.nix**

In `modules/gaming.nix`, add a `systemd.tmpfiles.rules` declaration inside the module output `{ ... }`:
```nix
  # Create /run/gamemode owned by the user so GameMode's custom start/end hooks
  # (touch / rm -f the flag file) work without elevated privileges.
  # /run is tmpfs — this directory is re-created on every boot.
  systemd.tmpfiles.rules = [
    "d /run/gamemode 0755 ${host.user} users -"
  ];
```

- [ ] **Step 3: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### Task 12: Remove spotify hotkey from plasma.nix

**Files:**
- Modify: `home/stoleyy/plasma.nix:79-82`

- [ ] **Step 1: Verify spotify is not installed**

```bash
grep -r spotify /etc/nixos/modules/ /etc/nixos/home/ 2>/dev/null | grep -v ".nix:" | grep -v "#"
```
Expected: only the plasma.nix hotkey line returns — no actual package declaration.

- [ ] **Step 2: Remove the hotkey block**

Lines 79–82 currently:
```nix
      "launch-spotify" = {
        key = "Meta+P";
        command = "spotify";
      };
```
Delete these 4 lines entirely. (Spotify was removed per the 2026-05-25 package audit.)

- [ ] **Step 3: Validate Wave 2 and commit**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: clean.

```bash
cd /etc/nixos && nixos-rebuild dry-build --flake .#predator 2>&1 | tail -5
```
Expected: `these 0 derivations will be built:` or similar (or a closure build that completes without errors).

```bash
git add -p  # stage only Wave 2 files
git commit -m "$(cat <<'EOF'
fix: wave 2 — correctness and safety fixes

- update-routines: host.user replaces hardcoded "stoleyy", sleep 1→5
- transcode: dedicated transcode group instead of generic "users"
- media-server: assertion enforces protonvpn.enable dependency
- browser: inherit theme colors, personal domain uses colors.bg1/bg2
- gamescope overlay: final: prev: explicit signature
- host.nix + gaming: IPC flag /tmp → /run/gamemode (tmpfiles-managed)
- plasma: remove spotify hotkey (package not installed)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Wave 3 — Deferred wiring (code-complete, nothing activates)

### Task 13: Clean up protonvpn sops wiring (it's already done — just cleanup)

**Files:**
- Modify: `modules/protonvpn.nix:80-82` (remove stale TODO)
- Modify: `hosts/predator/default.nix:108-111` (add restartUnits)

- [ ] **Step 1: Remove stale TODO from protonvpn.nix option description**

Lines 79–83 of `modules/protonvpn.nix` currently:
```nix
        Path to a root-owned mode-0400 file containing only the WireGuard
        private key (just the base64 string, no quotes, no header). NixOS
        won't read this file — wg-quick does at activation time. See
        docs/protonvpn-wg-setup.md for the one-liner to create it safely.

        Upgrade path: switch this to `config.sops.secrets.<name>.path` once
        sops-nix is wired up (Tier 2.1 in the optimization roadmap). At that
        point the private key lives encrypted in secrets.yaml.
```
Replace with:
```nix
        Path to a root-owned mode-0400 file containing only the WireGuard
        private key (just the base64 string, no quotes, no header). NixOS
        won't read this file — wg-quick does at activation time. See
        docs/protonvpn-wg-setup.md for setup instructions.

        Use config.sops.secrets.<name>.path (set in hosts/predator/default.nix)
        so the key is encrypted at rest in secrets/secrets.yaml.
```

- [ ] **Step 2: Add `restartUnits` to sops secret declaration**

In `hosts/predator/default.nix`, lines 108–111 currently:
```nix
  sops.secrets.protonvpn-private-key = {
    owner = "root";
    mode = "0400";
  };
```
Replace with:
```nix
  sops.secrets.protonvpn-private-key = {
    owner = "root";
    mode = "0400";
    restartUnits = [ "wg-quick-protonvpn.service" ];
  };
```
(When the encrypted secret is updated — e.g., key rotation — sops-nix automatically restarts wg-quick after re-decrypting.)

- [ ] **Step 3: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### Task 14: Add ollama.nix to lib/default.nix module list

**Files:**
- Modify: `lib/default.nix` — add ollama import

- [ ] **Step 1: Add ollama to the module list**

In `lib/default.nix`, find the section for monitoring/disabled services (around line 58):
```nix
        ../modules/monitoring.nix # ntfy, beszel, gatus, vector
```
Add after it (or in a logical place — e.g., after monitoring):
```nix
        ../modules/ollama.nix # Ollama LLM server (disabled — flip enable for local inference)
```

- [ ] **Step 2: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### Task 15: Add Wazuh secret stubs to secrets.yaml (USER-RUN STEP)

**Files:**
- Modify: `secrets/secrets.yaml` — via `sops` CLI (interactive, cannot be automated)

- [ ] **Step 1: Add placeholder secrets interactively**

This step must be run manually in a terminal:
```bash
cd /etc/nixos
sops secrets/secrets.yaml
```
In the editor that opens, add three new entries under the existing secrets:
```yaml
wazuh-indexer-password: CHANGEME
wazuh-api-password: CHANGEME
wazuh-dashboard-password: CHANGEME
```
Save and exit. sops will encrypt the new values.

- [ ] **Step 2: Validate secrets.yaml is parseable**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors (sops.validateSopsFiles = true will catch format errors at activation, not flake check).

---

### Task 16: Code-complete monitoring.nix (ntfy-failure template + vector tmpfiles)

**Files:**
- Modify: `modules/monitoring.nix:3` (signature), `:33-41` (uncomment ntfy template), `:138-139` (vector tmpfiles)

- [ ] **Step 1: Update module signature to expose pkgs, lib, and config**

Line 3 currently (after Wave 1 fix):
```nix
{ ... }:
```
Replace with:
```nix
{ pkgs, lib, config, ... }:
```

- [ ] **Step 2: Uncomment the ntfy-failure@ systemd template**

Lines 33–41 currently (commented out):
```nix
  # systemd.services = monitorOverrides // {
  #   "ntfy-failure@" = {
  #     description = "Notify on failure of %i";
  #     serviceConfig = {
  #       Type = "oneshot";
  #       ExecStart = "${pkgs.curl}/bin/curl -s -d 'Unit %i failed on ${hostname}' -H 'Title: Service Failure' -H 'Priority: high' -H 'Tags: rotating_light' ${ntfyUrl}/alerts";
  #     };
  #   };
  # };
```
Replace with the uncommented and corrected version (use `config.networking.hostName`):
```nix
  # OnFailure notification template. Activated only when ntfy-sh is running.
  # Usage: add `onFailure = [ "ntfy-failure@%n.service" ];` to any service.
  systemd.services."ntfy-failure@" = {
    description = "Notify on failure of %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.curl}/bin/curl -s -d 'Unit %i failed on ${config.networking.hostName}' -H 'Title: Service Failure' -H 'Priority: high' -H 'Tags: rotating_light' ${ntfyUrl}/alerts";
    };
  };
```

Note: This template fires into nothing when ntfy-sh is disabled (`enable = false`). It's harmless — curl will get connection refused. Once ntfy-sh is enabled, it works automatically.

- [ ] **Step 3: Add back vector tmpfiles rule**

Lines 138–139 currently:
```nix
  # tmpfiles rule removed — vector user doesn't exist when service is disabled.
  # Re-add when services.vector.enable is set back to true.
```
Replace with:
```nix
  # tmpfiles rule for vector log directory.
  # The vector user only exists when the service is enabled; wrapped in mkIf.
  systemd.tmpfiles.rules = lib.optionals config.services.vector.enable [
    "d /var/log/vector 0750 vector vector -"
  ];
```

- [ ] **Step 4: Validate**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -20
```
Expected: no errors.

---

### Task 17: Centralise monitor name in lib/host.nix and thread to consumers

**Files:**
- Modify: `lib/host.nix` — add `monitor` field
- Modify: `lib/default.nix` — add `host` to HM `extraSpecialArgs`
- Modify: `home/stoleyy/hyprland.nix:1,592` — add `host` arg, use `host.monitor`
- Modify: `hosts/predator/default.nix:266` — use `host.monitor` in gamescope args

- [ ] **Step 1: Add `monitor` to lib/host.nix**

`lib/host.nix` currently:
```nix
rec {
  user = "stoleyy";
  home = "/home/${user}";
  gamesDir = "${home}/games";
  mediaDir = "${gamesDir}/media";
  dataDir = "/data";
  # IPC flag: GameMode touches this to signal nvidia-undervolt to unlock clocks.
  gamemodeFlagFile = "/run/gamemode/gpu-unlock";
}
```
Add the `monitor` field:
```nix
rec {
  user = "stoleyy";
  home = "/home/${user}";
  gamesDir = "${home}/games";
  mediaDir = "${gamesDir}/media";
  dataDir = "/data";
  # Primary display output name — used in gamescope and wallpaper engine.
  # Change if monitor is connected to a different port (check: hyprctl monitors all).
  monitor = "DP-2";
  # IPC flag: GameMode touches this to signal nvidia-undervolt to unlock clocks.
  gamemodeFlagFile = "/run/gamemode/gpu-unlock";
}
```

- [ ] **Step 2: Expose `host` in HM extraSpecialArgs**

In `lib/default.nix`, lines 72–75 currently:
```nix
            extraSpecialArgs = {
              inherit inputs;
              theme = import ../lib/theme.nix;
            };
```
Replace with:
```nix
            extraSpecialArgs = {
              inherit inputs;
              host = import ../lib/host.nix;
              theme = import ../lib/theme.nix;
            };
```

- [ ] **Step 3: Use `host.monitor` in hyprland.nix wallpaper engine**

In `home/stoleyy/hyprland.nix`, line 1 currently:
```nix
{ pkgs, lib, theme, ... }:
```
Replace with:
```nix
{ pkgs, lib, theme, host, ... }:
```

Line 592 currently:
```nix
          ExecStart = "${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine --silent --screen-root DP-2 3510055857";
```
Replace with:
```nix
          ExecStart = "${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine --silent --screen-root ${host.monitor} 3510055857";
```

- [ ] **Step 4: Use `host.monitor` in gamescope args**

In `hosts/predator/default.nix`, the gamescope args section (around line 265–266) currently:
```nix
          "--prefer-output"
          "DP-2"
```
Replace with:
```nix
          "--prefer-output"
          host.monitor
```

- [ ] **Step 5: Validate Wave 3 and commit**

```bash
cd /etc/nixos && nix flake check --no-build 2>&1 | head -30
```
Expected: clean.

```bash
cd /etc/nixos && nixos-rebuild dry-build --flake .#predator 2>&1 | tail -10
```
Expected: build completes without errors.

```bash
git add -p  # stage Wave 3 files
git commit -m "$(cat <<'EOF'
feat: wave 3 — deferred wiring, code-complete, centralised config

- protonvpn: clean up stale TODO, add restartUnits to sops secret
- lib/default.nix: add ollama.nix to module list
- lib/default.nix: expose host identity to HM via extraSpecialArgs
- monitoring: fix signature, uncomment ntfy-failure@ template, vector tmpfiles
- lib/host.nix: add monitor field (DP-2) as single source of truth
- hyprland.nix: wallpaper engine uses host.monitor
- hosts/predator: gamescope --prefer-output uses host.monitor

Note: wazuh secret stubs require manual `sops secrets/secrets.yaml` step.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Final Checklist

- [ ] All 3 waves committed with passing `nix flake check --no-build`
- [ ] Wave 2 + Wave 3 also pass `nixos-rebuild dry-build --flake .#predator`
- [ ] Wazuh secrets stubs added manually via `sops secrets/secrets.yaml` (Task 15)
- [ ] Ready for `sudo nixos-rebuild test --flake .#predator` (run by user, not in this plan)
