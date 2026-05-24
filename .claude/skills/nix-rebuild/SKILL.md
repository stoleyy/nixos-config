---
name: nix-rebuild
description: "Use when rebuilding the NixOS system. Guides through the full validation pipeline: flake check -> dry-build -> test -> verify clean -> switch. Never skip steps."
---

# NixOS Rebuild Workflow

Execute the validation pipeline in order. Stop at any failure.

## Steps

1. **Eval check** (fast, catches syntax/type errors):
   ```bash
   nix flake check --no-build
   ```
   If this fails, fix the eval error before proceeding.

2. **Dry build** (full eval, shows what will be built):
   ```bash
   nixos-rebuild dry-build --flake .#predator
   ```
   Review the output. If the derivation path is unchanged from the current
   system, the config is already active (no-op).

3. **Test activation** (activates without making bootable):
   ```bash
   sudo nixos-rebuild test --flake .#predator
   ```
   This is reversible by reboot. Watch for `Failed to start` messages.

4. **Verify clean** (must pass before switch):
   ```bash
   systemctl --failed
   journalctl -p err -b 0 --no-pager | tail -20
   ```
   Both must show zero relevant failures. Pre-existing failures that
   existed before your changes are acceptable — note them.

5. **Switch** (makes the config the boot default — NOT reversible):
   ```bash
   sudo nixos-rebuild switch --flake .#predator
   ```
   Only run this if step 4 is clean.

6. **Diff** (what changed):
   ```bash
   nvd diff /run/booted-system /run/current-system
   ```

## Rules
- NEVER skip to switch without running test first
- If test fails, debug before retrying — do not retry blindly
- If the user asks to "just switch", warn them about the risk
- Use the nix-eval-debugger agent for eval failures
- Use the nix-build-fixer agent for build failures
- Use the nix-service-validator agent after test activation
