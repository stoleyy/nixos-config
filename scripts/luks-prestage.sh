#!/usr/bin/env bash
# Pre-stage data to games partition BEFORE rebooting into installer.
# Run as root from the running system. All NVMe-to-NVMe.
set -euo pipefail

STAGING="/home/stoleyy/games/.luks-staging"

echo "=== Pre-staging data to games partition ==="
echo "Destination: $STAGING"
echo

mkdir -p "$STAGING"

echo "=== 1/5: Staging /data (52G) ==="
mkdir -p "$STAGING/data-backup"
cp -av /data/. "$STAGING/data-backup/"

echo "=== 2/5: Staging home (131G, excluding games mount) ==="
mkdir -p "$STAGING/staging-home"
rsync -av --exclude='games' /home/stoleyy/ "$STAGING/staging-home/"

echo "=== 3/5: Staging system state (SSH keys, machine-id, service state) ==="
mkdir -p "$STAGING/staging-system"
cp -av /etc/ssh/ssh_host_ed25519_key     "$STAGING/staging-system/"
cp -av /etc/ssh/ssh_host_ed25519_key.pub "$STAGING/staging-system/"
cp -v  /etc/machine-id                   "$STAGING/staging-system/"

for d in sops-nix protonvpn jellyfin sonarr radarr prowlarr bazarr qbittorrent; do
    if [ -d "/var/lib/$d" ]; then
        echo "  Copying /var/lib/$d..."
        cp -a "/var/lib/$d" "$STAGING/staging-system/"
    fi
done

echo "=== 4/5: Staging NixOS config ==="
cp -a /etc/nixos "$STAGING/staging-system/nixos-config"

echo "=== 5/5: Syncing to disk ==="
sync

echo
echo "=== Pre-staging complete! ==="
du -sh "$STAGING"/*
df -h /home/stoleyy/games
echo
echo "Reboot into the NixOS installer USB now."
