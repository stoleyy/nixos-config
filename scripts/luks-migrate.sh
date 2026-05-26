#!/usr/bin/env bash
# LUKS Full-Disk Encryption Migration Script (NVMe-optimized, pre-staged)
# Run from the NixOS 25.11 graphical installer USB.
# Execute phases one at a time: phase1, phase2, phase3, phase4, phase5
#
# PREREQUISITE: luks-prestage.sh was run from the live system.
# All data is already at /dev/nvme1n1p2 → .luks-staging/
# sda/sdb are NEVER touched.
#
# See: docs/superpowers/specs/2026-05-26-luks-migration-design.md
set -euo pipefail

# ── Constants ──
NVME_DATA=/dev/nvme0n1p1        # /data (953.9G, 52G used)
NVME_MAIN=/dev/nvme1n1          # root + games + boot drive
NVME_GAMES=/dev/nvme1n1p2       # games (1.5T) — has .luks-staging/

# Mount points
MNT_DATA=/mnt/data-staging
MNT_GAMES_OLD=/mnt/games-old
STAGING=""                       # set after games is mounted

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
confirm() {
    blue "$1"
    read -rp "Press Enter to continue, Ctrl-C to abort... "
}

# ────────────────────────────────────────────────────────────────
# Phase 1: LUKS-encrypt /data, restore from pre-staged backup on games
# ────────────────────────────────────────────────────────────────
phase1() {
    green "=== Phase 1: Encrypt /data (nvme0n1p1) ==="

    # Mount games to access pre-staged data
    mkdir -p "$MNT_GAMES_OLD"
    mount "$NVME_GAMES" "$MNT_GAMES_OLD"
    STAGING="$MNT_GAMES_OLD/.luks-staging"

    # Verify pre-staged data exists
    if [ ! -d "$STAGING/data-backup" ]; then
        red "ERROR: Pre-staged data not found at $STAGING/data-backup"
        red "Did you run luks-prestage.sh from the live system first?"
        exit 1
    fi

    green "Pre-staged data found:"
    du -sh "$STAGING"/*

    confirm "Will LUKS-encrypt /data and restore from pre-staged backup on games partition."

    # 1a. LUKS-encrypt /data
    confirm "You will be prompted for the SINGLE passphrase. Remember it — this is the only passphrase for all 3 drives."
    blue "LUKS-encrypting nvme0n1p1..."
    cryptsetup luksFormat --type luks2 "$NVME_DATA"
    cryptsetup open "$NVME_DATA" cryptdata
    mkfs.ext4 -L data /dev/mapper/cryptdata

    # 1b. Restore /data from pre-staged backup (NVMe-to-NVMe, ~30s)
    blue "Restoring /data from pre-staged backup — NVMe speed..."
    mkdir -p "$MNT_DATA"
    mount /dev/mapper/cryptdata "$MNT_DATA"
    cp -av "$STAGING/data-backup/." "$MNT_DATA/"
    sync

    green "Phase 1 complete. /data is LUKS-encrypted."
    du -sh "$MNT_DATA"
    df -h "$MNT_DATA"
    blue "Run: $0 phase2"
}

# ────────────────────────────────────────────────────────────────
# Phase 2: Move pre-staged home + system + games onto encrypted /data
# ────────────────────────────────────────────────────────────────
phase2() {
    green "=== Phase 2: Move all pre-staged data to encrypted /data ==="

    # Ensure mounts
    if ! mountpoint -q "$MNT_DATA"; then
        mkdir -p "$MNT_DATA"
        cryptsetup open "$NVME_DATA" cryptdata 2>/dev/null || true
        mount /dev/mapper/cryptdata "$MNT_DATA"
    fi
    if ! mountpoint -q "$MNT_GAMES_OLD"; then
        mkdir -p "$MNT_GAMES_OLD"
        mount "$NVME_GAMES" "$MNT_GAMES_OLD"
    fi
    STAGING="$MNT_GAMES_OLD/.luks-staging"

    # 2a. Move pre-staged home to encrypted /data (NVMe-to-NVMe)
    blue "Moving home (143G) to encrypted /data — NVMe speed..."
    cp -av "$STAGING/staging-home" "$MNT_DATA/staging-home"

    # 2b. Move pre-staged system state to encrypted /data
    blue "Moving system state to encrypted /data..."
    cp -av "$STAGING/staging-system" "$MNT_DATA/staging-system"

    # 2c. Copy games (the actual game files, not the staging dir) to encrypted /data
    blue "Copying games (122G) to encrypted /data — NVMe speed..."
    mkdir -p "$MNT_DATA/staging-games"
    # Copy everything EXCEPT the staging directory itself
    find "$MNT_GAMES_OLD" -maxdepth 1 -not -name '.luks-staging' -not -path "$MNT_GAMES_OLD" -exec cp -av {} "$MNT_DATA/staging-games/" \;

    sync
    green "All data now on encrypted /data. Sizes:"
    du -sh "$MNT_DATA/staging-"* "$MNT_DATA/data-backup" 2>/dev/null || du -sh "$MNT_DATA"/*
    df -h "$MNT_DATA"

    # Unmount games — nvme1n1 is now expendable
    umount "$MNT_GAMES_OLD"

    green "Phase 2 complete. nvme1n1 is expendable — all data safe on encrypted /data."
    blue "Run: $0 phase3"
}

# ────────────────────────────────────────────────────────────────
# Phase 3: Repartition nvme1n1 + LUKS-encrypt games and root
# ────────────────────────────────────────────────────────────────
phase3() {
    green "=== Phase 3: Repartition + encrypt nvme1n1 ==="

    confirm "THIS WIPES nvme1n1. All data must be on encrypted /data (Phase 2). Continue?"

    # 3a. Repartition
    blue "Repartitioning nvme1n1..."
    sgdisk --zap-all "$NVME_MAIN"
    sgdisk -n 1:0:+1500G -t 1:8309 -c 1:cryptgames "$NVME_MAIN"
    sgdisk -n 2:0:+512M  -t 2:EF00 -c 2:boot       "$NVME_MAIN"
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
    blue "Run: $0 phase4"
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
    grep -n "by-uuid" "$HW_CONF" || true

    confirm "Verify UUIDs above look correct. nixos-install next."

    # 4f. nixos-install
    blue "Running nixos-install..."
    nixos-install --flake /mnt/etc/nixos#predator --no-root-passwd

    green "Phase 4 complete. System installed."
    blue "Run: $0 phase5"
}

# ────────────────────────────────────────────────────────────────
# Phase 5: Restore user data from staging
# ────────────────────────────────────────────────────────────────
phase5() {
    green "=== Phase 5: Restore data ==="

    # 5a. Restore home
    blue "Restoring home directory — NVMe speed..."
    cp -av /mnt/data/staging-home/. /mnt/home/stoleyy/
    mkdir -p /mnt/home/stoleyy/games
    chown -R 1000:100 /mnt/home/stoleyy

    # 5b. Restore games
    blue "Restoring games — NVMe speed..."
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
    sync
    green "Restored data sizes:"
    du -sh /mnt/home/stoleyy --exclude=/mnt/home/stoleyy/games
    du -sh /mnt/home/stoleyy/games
    du -sh /mnt/data

    green "Phase 5 complete."
    confirm "Verify sizes look right. Clean up staging and reboot?"

    # 5e. Clean up staging
    blue "Cleaning up staging directories..."
    rm -rf /mnt/data/staging-games /mnt/data/staging-home /mnt/data/staging-system /mnt/data/staging-boot /mnt/data/data-backup

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
        echo "LUKS Migration Script (NVMe-optimized, pre-staged)"
        echo "Usage: $0 {phase1|phase2|phase3|phase4|phase5}"
        echo
        echo "PREREQUISITE: Run luks-prestage.sh from the live system first."
        echo
        echo "Run phases IN ORDER from the NixOS installer USB:"
        echo "  phase1 — LUKS-encrypt /data, restore from pre-staged backup"
        echo "  phase2 — Move pre-staged data to encrypted /data"
        echo "  phase3 — Repartition nvme1n1, LUKS-encrypt games + root"
        echo "  phase4 — Mount, keyfile, UUID update, nixos-install"
        echo "  phase5 — Restore data, clean up, reboot"
        echo
        echo "All copies are NVMe-to-NVMe. sda/sdb never touched."
        ;;
esac
