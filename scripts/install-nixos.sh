#!/usr/bin/env bash
# NixOS installer — Acer Predator dual-boot
# Clones the flake from GitHub and installs in one shot.
#
# Usage:
#   sudo bash install-nixos.sh [<git-repo-url>]
#
#   Default repo: https://github.com/stoleyy/nixos-config.git
#
# Prereqs (already handled in this engagement):
#   - BIOS:  Secure Boot disabled, VMD disabled (drives in AHCI)
#   - Disk:  150 GB of unallocated space on the Samsung 980 Pro
#   - USB:   NixOS 25.11 graphical ISO booted

set -euo pipefail

REPO_URL="${1:-https://github.com/stoleyy/nixos-config.git}"

echo "========================================"
echo " NixOS Predator Installer"
echo " Repo: $REPO_URL"
echo "========================================"

# ── 1. Detect Samsung 980 Pro ─────────────────────────────────────────────────
echo "[1/7] Detecting Samsung SSD 980 Pro..."
DISK=$(lsblk -d -n -o NAME,MODEL | grep -i "980" | awk '{print "/dev/"$1}' | head -1 || true)

if [[ -z "$DISK" ]]; then
    echo "Auto-detect failed. Available disks:"
    lsblk -d -o NAME,SIZE,MODEL
    read -rp "Enter disk path (e.g. /dev/nvme1n1): " DISK
fi

echo "Target disk: $DISK"
lsblk "$DISK"
read -rp "Correct disk? [y/N]: " confirm
[[ "$confirm" == "y" ]] || { echo "Aborted."; exit 1; }

# ── 2. Create partitions in unallocated space ─────────────────────────────────
echo "[2/7] Creating EFI + root partitions in free space..."
sgdisk --new=0:0:+512M --typecode=0:EF00 --change-name=0:"NixOS EFI"  "$DISK"
sgdisk --new=0:0:0      --typecode=0:8300 --change-name=0:"NixOS Root" "$DISK"
partprobe "$DISK"
sleep 2

mapfile -t ALL_PARTS < <(lsblk -ln -o NAME,TYPE "$DISK" | awk '$2=="part"{print "/dev/"$1}' | sort -V)
EFI_PART="${ALL_PARTS[-2]}"
ROOT_PART="${ALL_PARTS[-1]}"
echo "EFI:  $EFI_PART"
echo "Root: $ROOT_PART"

# ── 3. Format ─────────────────────────────────────────────────────────────────
echo "[3/7] Formatting..."
mkfs.fat -F32 -n NIXOS_EFI  "$EFI_PART"
mkfs.ext4 -L  nixos-root -F "$ROOT_PART"

# ── 4. Mount ──────────────────────────────────────────────────────────────────
echo "[4/7] Mounting..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ── 5. Clone flake ────────────────────────────────────────────────────────────
echo "[5/7] Cloning flake from GitHub..."
# Live ISO may not have git in PATH — fall back to nix-shell
if ! command -v git >/dev/null 2>&1; then
    nix-shell -p git --run "git clone $REPO_URL /mnt/etc/nixos"
else
    git clone "$REPO_URL" /mnt/etc/nixos
fi

# ── 6. Hardware config ────────────────────────────────────────────────────────
echo "[6/7] Generating hardware-configuration.nix..."
nixos-generate-config --root /mnt
mv /mnt/etc/nixos/hardware-configuration.nix \
   /mnt/etc/nixos/hosts/predator/hardware-configuration.nix
rm -f /mnt/etc/nixos/configuration.nix

# ── 7. Install ────────────────────────────────────────────────────────────────
echo "[7/7] Running nixos-install..."
nixos-install --root /mnt \
    --flake /mnt/etc/nixos#predator \
    --extra-experimental-features "nix-command flakes"

echo ""
echo "========================================"
echo " Installation complete!"
echo "========================================"
echo ""
echo "Set your user password before rebooting:"
echo "  nixos-enter --root /mnt -c 'passwd stoleyy'"
echo ""
echo "Then reboot. Press F12 at POST to choose Samsung SSD."
