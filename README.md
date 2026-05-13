# nixos-config

Personal NixOS flake.

- **`predator`** — Acer Predator desktop, i7-13700K + RTX 4070, dual-boot with Windows on a Samsung 980 Pro 2TB.

## Layout

```text
flake.nix              entry — single host: predator
lib/default.nix        mkHost factory (add new hosts in one line)
modules/               composable system modules (base, networking, nvidia, …)
hosts/predator/        host overrides + hardware-configuration.nix
home/stoleyy/          home-manager config, split by concern
  ├── default.nix      aggregator
  ├── shell.nix        fish + starship + atuin + bash
  ├── terminal.nix     kitty
  ├── editor.nix       vscodium
  ├── browser.nix      firefox (hardened)
  ├── git.nix
  ├── gpg.nix
  └── audio.nix        easyeffects preset
overlays/              auto-imported — drop new .nix files in here
scripts/               install-nixos.sh + shrink-f.ps1
```

## Hardware support

| Hardware | Module / driver |
|---|---|
| NVIDIA RTX 4070 | `modules/nvidia.nix` (open kernel module + VA-API) |
| Intel i7-13700K | `nixos-hardware.common-cpu-intel-cpu-only` |
| Intel Wi-Fi 6E AX211 | `iwlwifi` + `hardware.enableRedistributableFirmware` |
| Killer E2600 Ethernet | `igc` + redistributable firmware |
| Intel Bluetooth | `hardware.bluetooth` + firmware |
| Realtek HD Audio | PipeWire |
| Logitech LIGHTSPEED | `hardware.logitech.wireless` (Solaar) |
| TPM 2.0 | `security.tpm2` |

Intel VMD is disabled in BIOS — NVMe drives appear as standard AHCI.

## Install (predator, dual-boot)

1. In Windows, run `scripts/shrink-f.ps1` as Administrator to free 150 GB on the Samsung SSD.
2. Boot the NixOS 25.11 graphical ISO from USB.
3. In the live environment:

   ```bash
   curl -O https://raw.githubusercontent.com/stoleyy/nixos-config/main/scripts/install-nixos.sh
   sudo bash install-nixos.sh
   ```

4. After install: `nixos-enter --root /mnt -c 'passwd stoleyy'` then reboot.

## Day-to-day

```bash
sudo nixos-rebuild switch --flake /etc/nixos#predator   # or alias `nb`
sudo nix flake update /etc/nixos                        # bump nixpkgs
```

## NTFS games partition (post-install)

```bash
sudo blkid /dev/nvme1n1p2   # grab the UUID of the Windows games partition
```

Add to `hosts/predator/default.nix`:

```nix
fileSystems."/games" = {
  device  = "/dev/disk/by-uuid/PASTE-UUID-HERE";
  fsType  = "ntfs3";
  options = [ "uid=1000" "gid=100" "dmask=022" "fmask=133" "nofail" "x-systemd.automount" ];
};
```

Disable Windows Fast Startup first or NTFS will be locked.

## Brave debloat

Brave runs with managed enterprise policy (`modules/apps.nix`) that disables Rewards, Wallet, AI Chat, News, Talk, VPN, Tor mode, P3A telemetry, and search suggestions. Sync is left on — sign in at `brave://sync` to pull search engines and bookmarks from Windows Brave.

## Adding a new host

Edit `flake.nix`:

```nix
nixosConfigurations.newhost = mkHost {
  hostName = "newhost";
  extraModules = [ ./modules/something.nix ];
};
```

Then create `hosts/newhost/default.nix` with the bootloader and host-specific bits. `mkHost` brings in every module from `modules/` plus home-manager and overlays automatically.
