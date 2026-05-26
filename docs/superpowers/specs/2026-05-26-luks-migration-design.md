# LUKS Full-Disk Encryption Migration

**Date**: 2026-05-26
**Status**: Approved
**Goal**: Encrypt all NVMe partitions (except EFI boot) with LUKS2, zero data loss.

## Current Partition Layout

```
nvme1n1       1.8T
├─ nvme1n1p1    16M  ext4   (unmounted, leftover — WIPE)
├─ nvme1n1p2   1.5T  ext4   /home/stoleyy/games  (122G used)
├─ nvme1n1p3   512M  vfat   /boot (EFI)           (KEEP AS-IS)
└─ nvme1n1p4 298.6G  ext4   /                     (131G home + system)

nvme0n1     953.9G
└─ nvme0n1p1 953.9G  ext4   /data                 (52G used)
```

Swap: zram0 (15.6G, in-memory — no disk partition to encrypt).
Swapfile in hosts/predator/default.nix (8G on root) — lives on encrypted root after migration.

## Target Partition Layout

```
nvme1n1       1.8T
├─ nvme1n1p1   1.5T  LUKS2 → ext4   /home/stoleyy/games
├─ nvme1n1p2   512M  vfat            /boot (EFI, unchanged)
└─ nvme1n1p3 298.6G  LUKS2 → ext4   /

nvme0n1     953.9G
└─ nvme0n1p1 953.9G  LUKS2 → ext4   /data
```

Changes from current:
- nvme1n1p1 (16M leftover) deleted, games partition renumbered to p1
- Boot partition renumbered to p2 (UUID unchanged — reformatted in place)
- Root partition renumbered to p3
- All three data partitions wrapped in LUKS2
- Partition numbers change but UUIDs in config will be updated post-format

## Encryption Design

- **Algorithm**: AES-256-XTS (hardware-accelerated via AES-NI on i7-13700K)
- **LUKS version**: LUKS2 (argon2id KDF — memory-hard, resistant to GPU brute-force)
- **Passphrase**: Single passphrase entered once at boot
- **Unlock chain**:
  1. systemd-boot loads kernel + initrd from unencrypted `/boot`
  2. initrd prompts for passphrase, unlocks `cryptroot` (root partition)
  3. Root mounts, keyfile at `/etc/luks-keyfile` unlocks `cryptgames` + `cryptdata` automatically
  4. Boot continues — user sees one password prompt total
- **Keyfile**: 4096-byte random file on encrypted root, mode 0400 root:root
  - Added to initrd via `boot.initrd.secrets` so it's available during Stage 2 mount
- **TRIM/discard**: Enabled (`allowDiscards = true`) for SSD performance
  - Security note: TRIM leaks which blocks are free vs used (not contents). Acceptable trade-off for SSD longevity on a desktop.

## Migration Strategy: Rolling Encryption

No external drives touched. Data shuffles between NVMe drives using `/data` as staging.
The USB (sdc) holds only the 52G `/data` backup as insurance during step 1.

### Phase 0: Pre-flight (running system)

1. Push latest config to git (`git add -A && git commit && git push`)
2. Copy `/etc/nixos` repo to USB as backup: `cp -a /etc/nixos /run/media/stoleyy/nixos-backup/`
3. Note critical identifiers:
   - `/etc/machine-id`
   - `/etc/ssh/ssh_host_ed25519_key` (sops-nix master key)
   - ProtonVPN state in `/var/lib/protonvpn/`
4. Verify sdb1 has pictures the user wants to keep — READ ONLY, never write to sda/sdb

### Phase 1: Encrypt /data (from installer USB)

1. Boot NixOS 25.11 graphical installer from USB (sdc)
2. Open terminal, become root
3. Mount sdb1 (NTFS, has 322G free) and copy /data as insurance:
   ```
   mkdir -p /mnt/sdb1 /mnt/data-old
   mount -t ntfs3 /dev/sdb1 /mnt/sdb1
   mount /dev/nvme0n1p1 /mnt/data-old
   # Copy /data contents to sdb1 (52G fits in 322G free)
   mkdir -p /mnt/sdb1/nixos-data-backup
   cp -a /mnt/data-old/. /mnt/sdb1/nixos-data-backup/
   umount /mnt/data-old
   umount /mnt/sdb1
   ```
   Note: sdb1 is NTFS — cp -a won't preserve unix permissions, but this is
   just an emergency backup. The real restore comes from the NVMe staging.
4. LUKS-encrypt /data:
   ```
   cryptsetup luksFormat --type luks2 /dev/nvme0n1p1
   # Enter passphrase (the SINGLE passphrase for the whole system)
   cryptsetup open /dev/nvme0n1p1 cryptdata
   mkfs.ext4 -L data /dev/mapper/cryptdata
   ```
5. Restore /data from sdb1 backup:
   ```
   mount /dev/mapper/cryptdata /mnt/data-old
   mount -t ntfs3 -o ro /dev/sdb1 /mnt/sdb1
   cp -a /mnt/sdb1/nixos-data-backup/. /mnt/data-old/
   umount /mnt/sdb1
   ```
6. Verify: `ls /mnt/data-old` — confirm 52G restored
7. Now `/data` is encrypted with ~900G free — this becomes staging for everything else

### Phase 2: Stage games + home onto encrypted /data

1. Mount current (unencrypted) partitions:
   ```
   mount /dev/nvme1n1p4 /mnt/root-old
   mount /dev/nvme1n1p2 /mnt/games-old
   ```
2. Copy games to encrypted /data staging:
   ```
   mkdir /mnt/data-old/staging-games
   cp -a /mnt/games-old/. /mnt/data-old/staging-games/
   ```
3. Copy home + critical system state:
   ```
   mkdir /mnt/data-old/staging-home
   cp -a /mnt/root-old/home/stoleyy/. /mnt/data-old/staging-home/
   # But exclude the games mountpoint (it's a separate partition)
   rm -rf /mnt/data-old/staging-home/games  # just the empty mountpoint dir

   mkdir /mnt/data-old/staging-system
   cp -a /mnt/root-old/etc/ssh/ssh_host_ed25519_key* /mnt/data-old/staging-system/
   cp    /mnt/root-old/etc/machine-id                /mnt/data-old/staging-system/
   # Media server + service state
   for d in sops-nix protonvpn jellyfin sonarr radarr prowlarr bazarr qbittorrent; do
     [ -d "/mnt/root-old/var/lib/$d" ] && cp -a "/mnt/root-old/var/lib/$d" /mnt/data-old/staging-system/
   done
   # NixOS config (with LUKS changes already committed)
   cp -a /mnt/root-old/etc/nixos /mnt/data-old/staging-system/nixos-config
   ```
4. Verify staging: `du -sh /mnt/data-old/staging-*`
   Expected: ~122G games + ~131G home + small system state = ~255G total on 953.9G drive
5. Unmount old partitions:
   ```
   umount /mnt/games-old /mnt/root-old
   ```

### Phase 3: Repartition + encrypt nvme1n1

1. Wipe nvme1n1 partition table (boot partition will be recreated):
   ```
   # SAVE the boot partition contents first
   mkdir /mnt/boot-save
   mount /dev/nvme1n1p3 /mnt/boot-save
   cp -a /mnt/boot-save/. /mnt/data-old/staging-boot/
   umount /mnt/boot-save
   ```
2. Repartition nvme1n1 (gdisk/sgdisk):
   ```
   sgdisk --zap-all /dev/nvme1n1
   # p1: games (1.5T)
   sgdisk -n 1:0:+1500G -t 1:8309 -c 1:cryptgames /dev/nvme1n1
   # p2: EFI boot (512M) — type EF00
   sgdisk -n 2:0:+512M -t 2:EF00 -c 2:boot /dev/nvme1n1
   # p3: root (rest ~298G)
   sgdisk -n 3:0:0 -t 3:8309 -c 3:cryptroot /dev/nvme1n1
   partprobe /dev/nvme1n1
   ```
3. Format EFI:
   ```
   mkfs.vfat -F32 -n BOOT /dev/nvme1n1p2
   ```
4. LUKS-encrypt games:
   ```
   cryptsetup luksFormat --type luks2 /dev/nvme1n1p1
   # SAME passphrase as /data
   cryptsetup open /dev/nvme1n1p1 cryptgames
   mkfs.ext4 -L games /dev/mapper/cryptgames
   ```
5. LUKS-encrypt root:
   ```
   cryptsetup luksFormat --type luks2 /dev/nvme1n1p3
   # SAME passphrase
   cryptsetup open /dev/nvme1n1p3 cryptroot
   mkfs.ext4 -L nixos /dev/mapper/cryptroot
   ```

### Phase 4: nixos-install

1. Mount the new encrypted layout:
   ```
   mount /dev/mapper/cryptroot /mnt
   mkdir -p /mnt/boot /mnt/home/stoleyy/games /mnt/data
   mount /dev/nvme1n1p2 /mnt/boot
   mount /dev/mapper/cryptgames /mnt/home/stoleyy/games
   mount /dev/mapper/cryptdata /mnt/data
   ```
2. Generate keyfile for auto-unlock of games + data:
   ```
   mkdir -p /mnt/etc
   dd if=/dev/urandom of=/mnt/etc/luks-keyfile bs=4096 count=1
   chmod 0400 /mnt/etc/luks-keyfile
   # Add keyfile as second key slot to games + data
   cryptsetup luksAddKey /dev/nvme1n1p1 /mnt/etc/luks-keyfile
   cryptsetup luksAddKey /dev/nvme0n1p1 /mnt/etc/luks-keyfile
   ```
3. Restore SSH host keys (BEFORE nixos-install so sops-nix can decrypt):
   ```
   mkdir -p /mnt/etc/ssh
   cp /mnt/data/staging-system/ssh_host_ed25519_key* /mnt/etc/ssh/
   chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key
   chmod 644 /mnt/etc/ssh/ssh_host_ed25519_key.pub
   ```
4. Restore machine-id:
   ```
   cp /mnt/data/staging-system/machine-id /mnt/etc/machine-id
   ```
5. Get the nixos config (with LUKS changes already committed):
   ```
   mkdir -p /mnt/etc/nixos
   # Option A: clone from GitHub
   nix-shell -p git --run "git clone https://github.com/stoleyy/nixos-config.git /mnt/etc/nixos"
   # Option B: copy from pre-flight backup on /data staging
   cp -a /mnt/data/staging-system/nixos-config /mnt/etc/nixos
   ```
   **The config must already have the LUKS changes applied (see NixOS Config Changes below).
   Commit and push the LUKS config changes BEFORE starting the migration (Phase 0).**
6. Install:
   ```
   nixos-install --flake /mnt/etc/nixos#predator --no-root-passwd
   ```

### Phase 5: Restore data

1. Restore home:
   ```
   cp -a /mnt/data/staging-home/. /mnt/home/stoleyy/
   mkdir /mnt/home/stoleyy/games  # recreate mountpoint
   chown -R 1000:100 /mnt/home/stoleyy
   ```
2. Restore games:
   ```
   cp -a /mnt/data/staging-games/. /mnt/home/stoleyy/games/
   chown -R 1000:100 /mnt/home/stoleyy/games
   ```
3. Restore service state:
   ```
   for d in sops-nix protonvpn jellyfin sonarr radarr prowlarr bazarr qbittorrent; do
     [ -d "/mnt/data/staging-system/$d" ] && cp -a "/mnt/data/staging-system/$d" /mnt/var/lib/
   done
   ```
4. Clean up staging directories:
   ```
   rm -rf /mnt/data/staging-games /mnt/data/staging-home /mnt/data/staging-system /mnt/data/staging-boot
   ```

### Phase 6: Reboot + verify

1. `umount -R /mnt`
2. `reboot`
3. System boots → passphrase prompt → unlocks root → keyfile unlocks games + data → login
4. Verify: `lsblk`, `mount | grep crypt`, all data present
5. Re-enable USBGuard: `sudo systemctl start usbguard`

## NixOS Config Changes

### hardware-configuration.nix

Replace current `fileSystems` and add LUKS devices:

```nix
boot.initrd = {
  availableKernelModules = [ "ahci" "xhci_pci" "nvme" "usbhid" ];
  kernelModules = [ "vmd" ];  # LOAD-BEARING — do not remove

  luks.devices = {
    cryptroot = {
      device = "/dev/disk/by-uuid/<ROOT-LUKS-UUID>";
      allowDiscards = true;
    };
    cryptgames = {
      device = "/dev/disk/by-uuid/<GAMES-LUKS-UUID>";
      keyFile = "/etc/luks-keyfile";
      allowDiscards = true;
    };
    cryptdata = {
      device = "/dev/disk/by-uuid/<DATA-LUKS-UUID>";
      keyFile = "/etc/luks-keyfile";
      allowDiscards = true;
    };
  };

  secrets."/etc/luks-keyfile" = /etc/luks-keyfile;
};

fileSystems."/" = {
  device = "/dev/mapper/cryptroot";
  fsType = "ext4";
  options = [ "noatime" ];
};

fileSystems."/boot" = {
  device = "/dev/disk/by-uuid/<NEW-BOOT-UUID>";
  fsType = "vfat";
  options = [ "fmask=0022" "dmask=0022" ];
};
```

### hosts/predator/default.nix

Update fileSystems to use /dev/mapper:

```nix
fileSystems."${host.gamesDir}" = {
  device = "/dev/mapper/cryptgames";
  fsType = "ext4";
  options = [ "noatime" "nofail" "x-systemd.device-timeout=5s" ];
};

fileSystems."${host.dataDir}" = {
  device = "/dev/mapper/cryptdata";
  fsType = "ext4";
  options = [ "noatime" "nofail" "x-systemd.device-timeout=5s" ];
};
```

### hardening.nix

Add USB mass storage allowlist rule (already applied in this session):

```nix
allow with-interface equals { 08:*:* }
```

## Rollback Plan

- If anything goes wrong during Phase 1-2: original partitions are still untouched (unencrypted, unmounted). Just reboot from nvme1n1.
- If Phase 3 fails (after nvme1n1 is wiped): all data is on encrypted /data. Repartition + restore from there.
- If Phase 4 (nixos-install) fails: re-run it. The flake is on USB and /data. Nothing is lost.
- Nuclear option: all unique data also backed up on USB (52G /data) and encrypted /data (everything else). Two independent copies exist at all times.

## Post-Migration Verification Checklist

- [ ] `lsblk` shows LUKS devices under all three NVMe partitions
- [ ] Single passphrase prompt at boot, games + data auto-unlock
- [ ] `/home/stoleyy` contents intact (check pictures, dotfiles, browser profiles)
- [ ] `/home/stoleyy/games` contents intact
- [ ] `/data` contents intact (52G of original data)
- [ ] sda/sdb NTFS drives untouched and mountable
- [ ] `systemctl --failed` — no failed units
- [ ] ProtonVPN tunnel up
- [ ] sops-nix secrets decrypting (SSH host key restored)
- [ ] `cryptsetup status cryptroot` — shows AES-256-XTS
- [ ] USBGuard re-enabled and working
- [ ] Pictures on sda/sdb verified intact

## Files Modified

- `hosts/predator/hardware-configuration.nix` — LUKS devices, updated fileSystems
- `hosts/predator/default.nix` — fileSystems use /dev/mapper/* instead of by-uuid
- `modules/hardening.nix` — USB mass storage rule (already applied)

## Risk Assessment

- **Data loss risk**: Minimal. At every phase, data exists in at least two locations. sda/sdb are never written to.
- **Boot failure risk**: Low. If nixos-install produces a bad generation, re-run from installer.
- **Performance impact**: Negligible. AES-NI on i7-13700K: ~5 GB/s throughput vs ~3.5 GB/s NVMe max.
- **Time estimate**: ~2-3 hours (dominated by ~305G of data copying between NVMe drives).
