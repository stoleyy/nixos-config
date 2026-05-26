# LUKS Full-Disk Encryption Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encrypt all three NVMe data partitions with LUKS2. Single passphrase at boot, keyfile auto-unlocks games + data. Zero data loss. sda/sdb never touched.

**Architecture:** Root partition unlocked by passphrase in initrd. Games + data auto-unlocked by a 4096-byte random keyfile embedded in the initrd via `boot.initrd.secrets`. Rolling encryption uses `/data` (953.9G, 52G used) as staging area. Config committed with UUID placeholders, replaced from the installer after formatting.

**Tech Stack:** NixOS 25.11, LUKS2/cryptsetup, systemd-boot, sgdisk, sops-nix

---

### Task 1: Update hardware-configuration.nix with LUKS + encrypted fileSystems

**Files:**
- Modify: `hosts/predator/hardware-configuration.nix` (full rewrite)

This is the core config change. LUKS device UUIDs are placeholders (`LUKS-ROOT-UUID`, `LUKS-GAMES-UUID`, `LUKS-DATA-UUID`, `BOOT-UUID`) — they get sed-replaced from the installer after formatting.

- [ ] **Step 1: Rewrite hardware-configuration.nix**

Replace the entire file content with:

```nix
# LUKS-encrypted NVMe layout. LUKS containers opened in initrd; fileSystems
# reference /dev/mapper/* names. User data mounts (games, /data) live in
# hosts/predator/default.nix for nofail + device-timeout handling.
#
# UUID placeholders (LUKS-ROOT-UUID, etc.) are replaced by the migration
# script after cryptsetup luksFormat. See docs/superpowers/specs/2026-05-26-luks-migration-design.md.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "ahci"
        "xhci_pci"
        "nvme"
        "usbhid"
      ];
      # LOAD-BEARING — do NOT remove or move to availableKernelModules. VMD is
      # disabled in BIOS but the controller persists; the kernel still needs vmd
      # to find the root NVMe by-UUID, force-loaded here so it inits before
      # Stage-1 root discovery (6.12+). Removing it = unbootable "cannot find
      # root" (PR #8 tried -> #13 bricked -> #14 this fix). Regen clobbers it.
      kernelModules = [ "vmd" ];

      luks.devices = {
        # Passphrase-prompted at boot. Single prompt — the only interactive unlock.
        cryptroot = {
          device = "/dev/disk/by-uuid/LUKS-ROOT-UUID";
          allowDiscards = true; # TRIM for SSD performance
        };
        # Auto-unlocked by keyfile embedded in the initrd.
        cryptgames = {
          device = "/dev/disk/by-uuid/LUKS-GAMES-UUID";
          keyFile = "/luks-keyfile";
          allowDiscards = true;
        };
        cryptdata = {
          device = "/dev/disk/by-uuid/LUKS-DATA-UUID";
          keyFile = "/luks-keyfile";
          allowDiscards = true;
        };
      };

      # Copy the keyfile from the root filesystem into the initrd at build time.
      # String path (not Nix path) so it resolves at activation, not eval.
      # During nixos-install this runs in the chroot (/mnt), finding /mnt/etc/luks-keyfile.
      secrets = {
        "/luks-keyfile" = "/etc/luks-keyfile";
      };
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
  };

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/BOOT-UUID";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
```

- [ ] **Step 2: Verify the file is syntactically valid**

Run: `nix-instantiate --parse hosts/predator/hardware-configuration.nix`
Expected: no parse errors (UUID placeholders are valid strings)

---

### Task 2: Update hosts/predator/default.nix fileSystems to use /dev/mapper

**Files:**
- Modify: `hosts/predator/default.nix:57-95` (fileSystems block + comments)

- [ ] **Step 1: Replace the games fileSystems block**

Replace:
```nix
  fileSystems."${host.gamesDir}" = {
    device = "/dev/disk/by-uuid/efd6d32e-54f9-4e6d-965f-67279a31da47";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };
```

With:
```nix
  fileSystems."${host.gamesDir}" = {
    device = "/dev/mapper/cryptgames";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };
```

- [ ] **Step 2: Replace the /data fileSystems block**

Replace:
```nix
  fileSystems."${host.dataDir}" = {
    device = "/dev/disk/by-uuid/88c50d98-1905-405d-a9c2-5ce522c9ad77";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };
```

With:
```nix
  fileSystems."${host.dataDir}" = {
    device = "/dev/mapper/cryptdata";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };
```

- [ ] **Step 3: Update the comment block above the fileSystems**

Replace the old UUID-focused comment (lines 57-62) with:
```nix
  # Intentional host data mounts live HERE, not in hardware-configuration.nix.
  # Both are LUKS-encrypted (opened in initrd via hardware-configuration.nix)
  # and referenced by their /dev/mapper names. nofail + device-timeout so a
  # LUKS failure degrades to a boot warning instead of a hard stop.
```

---

### Task 3: Verify config evaluates cleanly

**Files:** none (validation only)

- [ ] **Step 1: Run nix flake check**

Run: `nix flake check --no-build 2>&1 | head -20`
Expected: Clean eval. The UUID placeholders (`LUKS-ROOT-UUID` etc.) are just strings — NixOS doesn't validate them at eval time. If there are errors, they're structural, not UUID-related.

- [ ] **Step 2: Run nixfmt**

Run: `nix develop -c nixfmt hosts/predator/hardware-configuration.nix hosts/predator/default.nix`
Expected: Files formatted per project convention.

- [ ] **Step 3: Run statix + deadnix**

Run: `nix develop -c statix check hosts/predator/ && nix develop -c deadnix hosts/predator/`
Expected: Clean (same warnings as before, no new ones).

---

### Task 4: Create migration script

**Files:**
- Create: `scripts/luks-migrate.sh`

This is the step-by-step runbook executed from the NixOS installer USB. It's a script with functions for each phase — the user calls them one at a time, verifying between phases.

- [ ] **Step 1: Write the migration script**

```bash
#!/usr/bin/env bash
# LUKS Full-Disk Encryption Migration Script
# Run from the NixOS 25.11 graphical installer USB.
# Execute phases one at a time: phase1, phase2, phase3, phase4, phase5
#
# See: docs/superpowers/specs/2026-05-26-luks-migration-design.md
set -euo pipefail

# ── Constants ──
NVME_DATA=/dev/nvme0n1p1        # /data (953.9G)
NVME_MAIN=/dev/nvme1n1          # root + games + boot drive
BACKUP_DEV=/dev/sdb1            # NTFS backup (pictures — READ-ONLY after backup)
CONFIG_REPO="/mnt/data-staging/staging-system/nixos-config"

# Mount points (all under /mnt to avoid conflicts with installer)
MNT_DATA=/mnt/data-staging      # encrypted /data used as staging area
MNT_ROOT_OLD=/mnt/root-old
MNT_GAMES_OLD=/mnt/games-old
MNT_BACKUP=/mnt/sdb1-backup
MNT_TARGET=/mnt                 # nixos-install target

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
confirm() {
    blue "$1"
    read -rp "Press Enter to continue, Ctrl-C to abort... "
}

# ────────────────────────────────────────────────────────────────
# Phase 1: Backup /data to sdb1, then LUKS-encrypt /data
# ────────────────────────────────────────────────────────────────
phase1() {
    green "=== Phase 1: Encrypt /data (nvme0n1p1) ==="

    confirm "This will: backup /data (52G) to sdb1, then LUKS-encrypt nvme0n1p1."

    # 1a. Backup /data to NTFS drive (emergency copy)
    blue "Backing up /data to sdb1..."
    mkdir -p "$MNT_BACKUP" /mnt/data-old
    mount -t ntfs3 "$BACKUP_DEV" "$MNT_BACKUP"
    mount "$NVME_DATA" /mnt/data-old
    mkdir -p "$MNT_BACKUP/nixos-data-backup"
    cp -av /mnt/data-old/. "$MNT_BACKUP/nixos-data-backup/"
    green "Backup complete. Verifying..."
    du -sh "$MNT_BACKUP/nixos-data-backup"
    umount /mnt/data-old
    umount "$MNT_BACKUP"

    # 1b. LUKS-encrypt /data
    blue "LUKS-encrypting nvme0n1p1..."
    confirm "You will be prompted for the SINGLE passphrase. Remember it — this is the only passphrase for all 3 drives."
    cryptsetup luksFormat --type luks2 "$NVME_DATA"
    cryptsetup open "$NVME_DATA" cryptdata
    mkfs.ext4 -L data /dev/mapper/cryptdata

    # 1c. Restore /data from sdb1 backup
    blue "Restoring /data from sdb1 backup..."
    mkdir -p "$MNT_DATA"
    mount /dev/mapper/cryptdata "$MNT_DATA"
    mount -t ntfs3 -o ro "$BACKUP_DEV" "$MNT_BACKUP"
    cp -av "$MNT_BACKUP/nixos-data-backup/." "$MNT_DATA/"
    umount "$MNT_BACKUP"

    green "Phase 1 complete. /data is now LUKS-encrypted with ~900G free staging space."
    du -sh "$MNT_DATA"
    blue "Verify your data above, then run: phase2"
}

# ────────────────────────────────────────────────────────────────
# Phase 2: Stage games + home + system state onto encrypted /data
# ────────────────────────────────────────────────────────────────
phase2() {
    green "=== Phase 2: Stage all data onto encrypted /data ==="

    # Ensure /data is mounted
    if ! mountpoint -q "$MNT_DATA"; then
        mount /dev/mapper/cryptdata "$MNT_DATA"
    fi

    # 2a. Mount old unencrypted partitions
    blue "Mounting old root and games partitions..."
    mkdir -p "$MNT_ROOT_OLD" "$MNT_GAMES_OLD"
    mount /dev/nvme1n1p4 "$MNT_ROOT_OLD"
    mount /dev/nvme1n1p2 "$MNT_GAMES_OLD"

    # 2b. Copy games
    blue "Copying games (122G) to staging..."
    mkdir -p "$MNT_DATA/staging-games"
    cp -av "$MNT_GAMES_OLD/." "$MNT_DATA/staging-games/"

    # 2c. Copy home (excluding games mountpoint)
    blue "Copying home directory to staging..."
    mkdir -p "$MNT_DATA/staging-home"
    cp -av "$MNT_ROOT_OLD/home/stoleyy/." "$MNT_DATA/staging-home/"
    # Remove the empty games mountpoint dir (it's a separate partition)
    rm -rf "$MNT_DATA/staging-home/games"

    # 2d. Copy critical system state
    blue "Copying system state (SSH keys, machine-id, service state)..."
    mkdir -p "$MNT_DATA/staging-system"
    cp -av "$MNT_ROOT_OLD/etc/ssh/ssh_host_ed25519_key"     "$MNT_DATA/staging-system/"
    cp -av "$MNT_ROOT_OLD/etc/ssh/ssh_host_ed25519_key.pub" "$MNT_DATA/staging-system/"
    cp -v  "$MNT_ROOT_OLD/etc/machine-id"                   "$MNT_DATA/staging-system/"

    for d in sops-nix protonvpn jellyfin sonarr radarr prowlarr bazarr qbittorrent; do
        if [ -d "$MNT_ROOT_OLD/var/lib/$d" ]; then
            blue "  Copying /var/lib/$d..."
            cp -a "$MNT_ROOT_OLD/var/lib/$d" "$MNT_DATA/staging-system/"
        fi
    done

    # 2e. Copy NixOS config
    blue "Copying NixOS config..."
    cp -a "$MNT_ROOT_OLD/etc/nixos" "$MNT_DATA/staging-system/nixos-config"

    # 2f. Save boot partition
    blue "Saving boot partition contents..."
    mkdir -p /mnt/boot-save "$MNT_DATA/staging-boot"
    mount /dev/nvme1n1p3 /mnt/boot-save
    cp -av /mnt/boot-save/. "$MNT_DATA/staging-boot/"
    umount /mnt/boot-save

    # 2g. Verify and unmount
    green "Staging complete. Sizes:"
    du -sh "$MNT_DATA/staging-"*
    df -h "$MNT_DATA"

    umount "$MNT_GAMES_OLD" "$MNT_ROOT_OLD"

    green "Phase 2 complete. All data staged on encrypted /data."
    blue "Verify the sizes above look right, then run: phase3"
}

# ────────────────────────────────────────────────────────────────
# Phase 3: Repartition nvme1n1 + LUKS-encrypt games and root
# ────────────────────────────────────────────────────────────────
phase3() {
    green "=== Phase 3: Repartition + encrypt nvme1n1 ==="

    confirm "THIS WIPES nvme1n1. All data must be on /data staging (Phase 2). Continue?"

    # 3a. Repartition
    blue "Repartitioning nvme1n1..."
    sgdisk --zap-all "$NVME_MAIN"
    # p1: games (~1.5T)
    sgdisk -n 1:0:+1500G -t 1:8309 -c 1:cryptgames "$NVME_MAIN"
    # p2: EFI boot (512M)
    sgdisk -n 2:0:+512M  -t 2:EF00 -c 2:boot       "$NVME_MAIN"
    # p3: root (remaining ~298G)
    sgdisk -n 3:0:0      -t 3:8309 -c 3:cryptroot   "$NVME_MAIN"
    partprobe "$NVME_MAIN"
    sleep 2
    green "New partition table:"
    sgdisk -p "$NVME_MAIN"

    # 3b. Format EFI
    blue "Formatting EFI partition..."
    mkfs.vfat -F32 -n BOOT /dev/nvme1n1p2

    # 3c. LUKS-encrypt games
    blue "LUKS-encrypting games partition (nvme1n1p1)..."
    confirm "Enter the SAME passphrase you used for /data."
    cryptsetup luksFormat --type luks2 /dev/nvme1n1p1
    cryptsetup open /dev/nvme1n1p1 cryptgames
    mkfs.ext4 -L games /dev/mapper/cryptgames

    # 3d. LUKS-encrypt root
    blue "LUKS-encrypting root partition (nvme1n1p3)..."
    confirm "Enter the SAME passphrase again."
    cryptsetup luksFormat --type luks2 /dev/nvme1n1p3
    cryptsetup open /dev/nvme1n1p3 cryptroot
    mkfs.ext4 -L nixos /dev/mapper/cryptroot

    green "Phase 3 complete. All three drives are LUKS-encrypted."
    lsblk -o NAME,SIZE,FSTYPE /dev/nvme0n1 /dev/nvme1n1
    blue "Run: phase4"
}

# ────────────────────────────────────────────────────────────────
# Phase 4: Mount, generate keyfile, update config UUIDs, nixos-install
# ────────────────────────────────────────────────────────────────
phase4() {
    green "=== Phase 4: nixos-install ==="

    # 4a. Mount encrypted layout at /mnt
    blue "Mounting encrypted layout..."
    mount /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/boot /mnt/home/stoleyy/games /mnt/data
    mount /dev/nvme1n1p2 /mnt/boot
    mount /dev/mapper/cryptgames /mnt/home/stoleyy/games
    # /data staging is already mounted; remount at target path
    umount "$MNT_DATA" 2>/dev/null || true
    mount /dev/mapper/cryptdata /mnt/data

    # 4b. Generate keyfile for auto-unlock
    blue "Generating LUKS keyfile..."
    mkdir -p /mnt/etc
    dd if=/dev/urandom of=/mnt/etc/luks-keyfile bs=4096 count=1
    chmod 0400 /mnt/etc/luks-keyfile

    blue "Adding keyfile to games + data LUKS slots..."
    confirm "Enter the SAME passphrase to authorize adding the keyfile."
    cryptsetup luksAddKey /dev/nvme1n1p1 /mnt/etc/luks-keyfile
    cryptsetup luksAddKey /dev/nvme0n1p1 /mnt/etc/luks-keyfile

    # 4c. Restore SSH host keys (BEFORE nixos-install so sops-nix works)
    blue "Restoring SSH host keys + machine-id..."
    mkdir -p /mnt/etc/ssh
    cp /mnt/data/staging-system/ssh_host_ed25519_key     /mnt/etc/ssh/
    cp /mnt/data/staging-system/ssh_host_ed25519_key.pub /mnt/etc/ssh/
    chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key
    chmod 644 /mnt/etc/ssh/ssh_host_ed25519_key.pub
    cp /mnt/data/staging-system/machine-id /mnt/etc/machine-id

    # 4d. Get NixOS config
    blue "Restoring NixOS config..."
    cp -a /mnt/data/staging-system/nixos-config /mnt/etc/nixos

    # 4e. Replace UUID placeholders with real LUKS UUIDs
    blue "Detecting LUKS UUIDs..."
    ROOT_UUID=$(blkid -s UUID -o value /dev/nvme1n1p3)
    GAMES_UUID=$(blkid -s UUID -o value /dev/nvme1n1p1)
    DATA_UUID=$(blkid -s UUID -o value /dev/nvme0n1p1)
    BOOT_UUID=$(blkid -s UUID -o value /dev/nvme1n1p2)

    green "UUIDs detected:"
    echo "  Root:  $ROOT_UUID"
    echo "  Games: $GAMES_UUID"
    echo "  Data:  $DATA_UUID"
    echo "  Boot:  $BOOT_UUID"

    blue "Replacing placeholders in hardware-configuration.nix..."
    HW_CONF="/mnt/etc/nixos/hosts/predator/hardware-configuration.nix"
    sed -i "s/LUKS-ROOT-UUID/$ROOT_UUID/g"   "$HW_CONF"
    sed -i "s/LUKS-GAMES-UUID/$GAMES_UUID/g" "$HW_CONF"
    sed -i "s/LUKS-DATA-UUID/$DATA_UUID/g"   "$HW_CONF"
    sed -i "s/BOOT-UUID/$BOOT_UUID/g"        "$HW_CONF"

    green "Updated hardware-configuration.nix:"
    grep -n "uuid\|UUID\|by-uuid\|mapper" "$HW_CONF" || true

    confirm "Verify UUIDs above look correct. nixos-install next."

    # 4f. nixos-install
    blue "Running nixos-install..."
    nixos-install --flake /mnt/etc/nixos#predator --no-root-passwd

    green "Phase 4 complete. System installed."
    blue "Run: phase5"
}

# ────────────────────────────────────────────────────────────────
# Phase 5: Restore user data from staging
# ────────────────────────────────────────────────────────────────
phase5() {
    green "=== Phase 5: Restore data ==="

    # 5a. Restore home
    blue "Restoring home directory..."
    cp -av /mnt/data/staging-home/. /mnt/home/stoleyy/
    mkdir -p /mnt/home/stoleyy/games   # recreate mountpoint
    chown -R 1000:100 /mnt/home/stoleyy

    # 5b. Restore games
    blue "Restoring games..."
    cp -av /mnt/data/staging-games/. /mnt/home/stoleyy/games/
    chown -R 1000:100 /mnt/home/stoleyy/games

    # 5c. Restore service state
    blue "Restoring service state..."
    for d in sops-nix protonvpn jellyfin sonarr radarr prowlarr bazarr qbittorrent; do
        if [ -d "/mnt/data/staging-system/$d" ]; then
            blue "  Restoring /var/lib/$d..."
            cp -a "/mnt/data/staging-system/$d" /mnt/var/lib/
        fi
    done

    # 5d. Verify
    green "Restored data sizes:"
    du -sh /mnt/home/stoleyy --exclude=/mnt/home/stoleyy/games
    du -sh /mnt/home/stoleyy/games
    du -sh /mnt/data

    green "Phase 5 complete."
    confirm "Verify sizes look right. Clean up staging and reboot?"

    # 5e. Clean up staging
    blue "Cleaning up staging directories..."
    rm -rf /mnt/data/staging-games /mnt/data/staging-home /mnt/data/staging-system /mnt/data/staging-boot

    # 5f. Unmount and reboot
    blue "Unmounting..."
    umount -R /mnt

    green "=== Migration complete! ==="
    green "Reboot now. You'll see ONE passphrase prompt, then normal boot."
    green "After boot, verify with: lsblk, mount | grep crypt, systemctl --failed"
    echo
    blue "Post-boot: commit the real UUIDs to git and push:"
    blue "  cd /etc/nixos && git add -A && git commit -m 'feat: LUKS encryption — real UUIDs' && git push"
    echo
    confirm "Ready to reboot?"
    reboot
}

# ────────────────────────────────────────────────────────────────
# Dispatch
# ────────────────────────────────────────────────────────────────
case "${1:-help}" in
    phase1) phase1 ;;
    phase2) phase2 ;;
    phase3) phase3 ;;
    phase4) phase4 ;;
    phase5) phase5 ;;
    *)
        echo "LUKS Migration Script"
        echo "Usage: $0 {phase1|phase2|phase3|phase4|phase5}"
        echo
        echo "Run phases IN ORDER from the NixOS installer USB:"
        echo "  phase1 — Backup /data to sdb1, LUKS-encrypt /data, restore"
        echo "  phase2 — Stage games + home + system onto encrypted /data"
        echo "  phase3 — Repartition nvme1n1, LUKS-encrypt games + root"
        echo "  phase4 — Mount, keyfile, UUID update, nixos-install"
        echo "  phase5 — Restore data, clean up, reboot"
        ;;
esac
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x scripts/luks-migrate.sh`

---

### Task 5: Validate and commit all changes

**Files:** none (git operations)

- [ ] **Step 1: Run full linter suite**

Run:
```bash
nix develop -c nixfmt hosts/predator/hardware-configuration.nix hosts/predator/default.nix
nix develop -c statix check .
nix develop -c deadnix .
```
Expected: clean (same as before, no new warnings)

- [ ] **Step 2: Run nix flake check**

Run: `nix flake check --no-build`
Expected: clean eval

- [ ] **Step 3: Commit all changes**

```bash
git add hosts/predator/hardware-configuration.nix hosts/predator/default.nix modules/hardening.nix scripts/luks-migrate.sh docs/superpowers/specs/2026-05-26-luks-migration-design.md docs/superpowers/plans/2026-05-26-luks-migration.md
git commit -m "feat: LUKS full-disk encryption — config + migration script

LUKS2 on all three NVMe data partitions (root, games, /data).
Single passphrase at boot; keyfile auto-unlocks games + data.
UUID placeholders replaced by migration script after formatting.
Rolling encryption strategy: /data as staging, sda/sdb untouched.

See docs/superpowers/specs/2026-05-26-luks-migration-design.md"
```

- [ ] **Step 4: Push to remote**

Run: `git push origin main`

This ensures the config is on GitHub as a backup. The migration script
is also in the repo, accessible from the installer via git clone.

---

### Task 6: Execute Phase 0 pre-flight (on running system, before reboot)

**Files:** none (manual verification)

- [ ] **Step 1: Verify critical files exist**

Run:
```bash
ls -la /etc/ssh/ssh_host_ed25519_key*
cat /etc/machine-id
ls -la /var/lib/sops-nix/
ls -la /var/lib/protonvpn/
```
Expected: all present and non-empty

- [ ] **Step 2: Copy migration script to USB**

The USB (sdc) is the NixOS installer — it's iso9660 (read-only). Mount it
and note the script will be accessible from /data staging after Phase 2.
Alternatively, the script is on GitHub after Task 5.

From the installer, fetch via:
```bash
nix-shell -p git --run "git clone https://github.com/stoleyy/nixos-config.git /tmp/nixos-config"
bash /tmp/nixos-config/scripts/luks-migrate.sh phase1
```

Or copy to a writable location before reboot:
```bash
cp /etc/nixos/scripts/luks-migrate.sh /tmp/
```

- [ ] **Step 3: Reboot into NixOS installer USB**

Reboot, hold Space at systemd-boot, select the USB entry.

---

### Task 7: Execute migration from installer (manual — phases 1-5)

This task is performed manually by the user from the NixOS installer terminal.

- [ ] **Step 1: Get the migration script**

```bash
sudo -i
nix-shell -p git --run "git clone https://github.com/stoleyy/nixos-config.git /tmp/nixos-config"
```

- [ ] **Step 2: Run phase1 — encrypt /data**

```bash
bash /tmp/nixos-config/scripts/luks-migrate.sh phase1
```
Verify: `du -sh /mnt/data-staging` shows ~52G of original /data content

- [ ] **Step 3: Run phase2 — stage everything to encrypted /data**

```bash
bash /tmp/nixos-config/scripts/luks-migrate.sh phase2
```
Verify: `du -sh /mnt/data-staging/staging-*` shows ~122G games + ~131G home + system state

- [ ] **Step 4: Run phase3 — repartition + encrypt nvme1n1**

```bash
bash /tmp/nixos-config/scripts/luks-migrate.sh phase3
```
Verify: `lsblk` shows LUKS containers on both NVMe drives

- [ ] **Step 5: Run phase4 — nixos-install**

```bash
bash /tmp/nixos-config/scripts/luks-migrate.sh phase4
```
Verify: nixos-install completes without errors. UUIDs replaced in hardware-configuration.nix.

- [ ] **Step 6: Run phase5 — restore data + reboot**

```bash
bash /tmp/nixos-config/scripts/luks-migrate.sh phase5
```
Verify: reboot → single passphrase prompt → login → all data intact

---

### Task 8: Post-migration verification + commit real UUIDs

- [ ] **Step 1: Verify encryption**

Run:
```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
cryptsetup status cryptroot
cryptsetup status cryptgames
cryptsetup status cryptdata
```
Expected: all three show `cipher: aes-xts-plain64`, `keysize: 512 bits`

- [ ] **Step 2: Verify data integrity**

Run:
```bash
ls ~/games/
ls ~/
du -sh /data
mount | grep crypt
```
Expected: all files present, all three mounts via mapper devices

- [ ] **Step 3: Verify system health**

Run:
```bash
systemctl --failed
journalctl -p err -b 0 | head -20
ping -c 3 1.1.1.1
```
Expected: no failed units, no errors, VPN + internet working

- [ ] **Step 4: Verify sops-nix**

Run:
```bash
sudo cat /run/secrets/protonvpn-private-key | head -c 10
```
Expected: outputs first 10 chars of the decrypted key (proves sops-nix + SSH key chain works)

- [ ] **Step 5: Verify sda/sdb pictures untouched**

Run:
```bash
sudo mount -t ntfs3 -o ro /dev/sda2 /tmp/sda2
ls /tmp/sda2/
sudo umount /tmp/sda2
sudo mount -t ntfs3 -o ro /dev/sdb1 /tmp/sdb1
ls /tmp/sdb1/
sudo umount /tmp/sdb1
```
Expected: all NTFS content intact, pictures present

- [ ] **Step 6: Commit real UUIDs and push**

```bash
cd /etc/nixos
git add -A
git commit -m "feat: LUKS encryption — real UUIDs after migration"
git push origin main
```

- [ ] **Step 7: Clean up sdb1 backup**

Once everything is verified working across a reboot:
```bash
sudo mount -t ntfs3 /dev/sdb1 /tmp/sdb1
sudo rm -rf /tmp/sdb1/nixos-data-backup
sudo umount /tmp/sdb1
```

- [ ] **Step 8: Re-enable USBGuard**

```bash
sudo systemctl start usbguard
sudo systemctl status usbguard
```

- [ ] **Step 9: Update CLAUDE.md with LUKS info**

Add to the Hardware section and Pitfalls:
- All NVMe partitions LUKS2-encrypted
- Single passphrase at boot, keyfile auto-unlocks secondary volumes
- `/etc/luks-keyfile` is critical — never delete, included in initrd via `boot.initrd.secrets`
- After `nixos-generate-config`: re-apply VMD kernelModule AND re-add luks.devices block
