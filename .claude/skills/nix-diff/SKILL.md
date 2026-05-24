---
name: nix-diff
description: "Use when comparing NixOS generations or understanding what changed between rebuilds. Uses nvd for package-level diff and nix-diff for derivation-level diff."
---

# NixOS Generation Diff

## Quick Diff (what packages changed)
```bash
nvd diff /run/booted-system /run/current-system
```

## Deep Diff (why a rebuild was triggered)
```bash
nix-diff /run/booted-system /run/current-system
```
This shows which derivation inputs changed. Useful when a rebuild
is unexpectedly large.

## Historical Diff (between specific generations)
```bash
# List generations
nixos-rebuild list-generations --flake .#predator | head -10

# Diff two generations (replace paths)
nvd diff /nix/var/nix/profiles/system-N-link /nix/var/nix/profiles/system-M-link
```

## Closure Size Tracking
```bash
nix path-info -Sh /run/current-system
```

## Rules
- Always run nvd first (fast, human-readable)
- Use nix-diff only when you need to understand WHY something rebuilt
- Report closure size changes if they exceed 100MB
