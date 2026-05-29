# nixos-config

Personal NixOS 25.11 flake for a single desktop host, **`predator`**
(Acer Predator — Intel i7-13700K, RTX 4070, 64 GB).

> **Full architecture, conventions, rebuild workflow, and the hard-won
> pitfalls live in [`CLAUDE.md`](./CLAUDE.md).** That file is the
> authoritative reference; this README is just a pointer so the two don't
> drift.

## At a glance

- `flake.nix` — inputs + the single `nixosConfigurations.predator` entry.
- `lib/default.nix` — the `mkHost` factory and the **curated** system-module
  list (the canonical list lives here, not in `flake.nix`).
- `modules/`, `home/stoleyy/`, `hosts/predator/`, `overlays/` — system
  modules, home-manager config, host hardware, and auto-imported overlays.

See CLAUDE.md → "Repo layout" for the complete map.

## Install (predator)

1. Boot the NixOS 25.11 graphical ISO from USB.
2. In the live environment:

   ```bash
   curl -O https://raw.githubusercontent.com/stoleyy/nixos-config/main/scripts/install-nixos.sh
   sudo bash install-nixos.sh
   ```

3. After install: `nixos-enter --root /mnt -c 'passwd stoleyy'`, then reboot.

## Rebuild

```bash
sudo nixos-rebuild switch --flake /etc/nixos#predator
```

The full validation pipeline (`flake check` → `dry-build` → `test` →
`switch`) and rollback strategy are documented in CLAUDE.md → "Rebuilding"
and "Workflow loop".
