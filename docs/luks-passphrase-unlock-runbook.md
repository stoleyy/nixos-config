# Runbook: remove the initrd LUKS keyfile (single-passphrase unlock)

**Goal:** stop auto-unlocking `/games` and `/data` with a keyfile baked into the
initramfs on the **unencrypted `/boot` ESP** (which makes both volumes
decryptable from a dead-box disk image without any passphrase — see
`docs/linuxleo-forensic-analysis.md`). Switch all three LUKS volumes to unlock
from the **single passphrase already enrolled in their keyslots** (migration
spec Phase 3), via **systemd-initrd** password caching. End state: one passphrase
prompt, all volumes open, **no key material on `/boot`**.

> ⚠️ These steps run **on the machine** (`/etc/nixos` is the active flake) and
> involve `cryptsetup` + a reboot. A wrong move can render the box unbootable —
> this host has a VMD/initrd brick history (PR #8 → #13 → #14). Have a NixOS
> installer USB ready and **do not remove the keyfile keyslot until
> passphrase-only boot is confirmed (Step 4).**

## 0. Confirm device UUIDs on-box

Trust on-box `blkid`/`lsblk`, never the device node (CLAUDE.md pitfall):

```bash
lsblk -o NAME,UUID,FSTYPE,MOUNTPOINT
# Expected LUKS container UUIDs (verify against the running box):
#   cryptroot  6ebbc3fa-7297-48d3-bf7d-6d2a5a3fcb9c
#   cryptgames 9cb83a31-102e-440f-9fea-f6c86dbefea8
#   cryptdata  25748fb8-febe-42af-9a95-98980ca89751
```

## 1. Verify the passphrase unlocks games + data (CRITICAL — do this first)

`--test-passphrase` checks a slot without opening the device. Enter the system
passphrase when prompted; exit code 0 = the passphrase is in a keyslot:

```bash
sudo cryptsetup open --test-passphrase /dev/disk/by-uuid/9cb83a31-102e-440f-9fea-f6c86dbefea8 && echo "games: passphrase OK"
sudo cryptsetup open --test-passphrase /dev/disk/by-uuid/25748fb8-febe-42af-9a95-98980ca89751 && echo "data: passphrase OK"
```

If either fails, **stop** — enroll the passphrase first
(`sudo cryptsetup luksAddKey <dev>`) before proceeding.

Inspect the keyslots (expect a passphrase slot *and* the keyfile slot):

```bash
sudo cryptsetup luksDump /dev/disk/by-uuid/9cb83a31-102e-440f-9fea-f6c86dbefea8 | sed -n '/Keyslots/,/Tokens/p'
```

## 2. Apply the config changes (keyfile slot still intact as fallback)

In `hosts/predator/hardware-configuration.nix`:

```diff
   boot = {
     initrd = {
       availableKernelModules = [ "ahci" "xhci_pci" "nvme" "usbhid" ];
       kernelModules = [ "vmd" ];   # LOAD-BEARING — keep (systemd-initrd honours it)

+      # Use systemd-initrd: it caches the entered passphrase in the kernel
+      # keyring and retries it on every LUKS device, so the single passphrase
+      # enrolled in all three slots unlocks everything — no keyfile needed.
+      systemd.enable = true;
+
       luks.devices = {
         cryptroot = {
           device = "/dev/disk/by-uuid/6ebbc3fa-7297-48d3-bf7d-6d2a5a3fcb9c";
           allowDiscards = true;
         };
         cryptgames = {
           device = "/dev/disk/by-uuid/9cb83a31-102e-440f-9fea-f6c86dbefea8";
-          keyFile = "/luks-keyfile";
           allowDiscards = true;
         };
         cryptdata = {
           device = "/dev/disk/by-uuid/25748fb8-febe-42af-9a95-98980ca89751";
-          keyFile = "/luks-keyfile";
           allowDiscards = true;
         };
       };
-
-      # Copy the keyfile from the root filesystem into the initrd at build time.
-      secrets = {
-        "/luks-keyfile" = "/etc/luks-keyfile";
-      };
     };
     kernelModules = [ "kvm-intel" ];
     extraModulePackages = [ ];
   };
```

Validate (CLAUDE.md pipeline — never skip ahead):

```bash
cd /etc/nixos
nix flake check --no-build
nixos-rebuild dry-build --flake .#predator
sudo nixos-rebuild test --flake .#predator   # builds initrd; not the bootloader yet
```

## 3. Reboot test — confirm passphrase-only unlock works

```bash
sudo nixos-rebuild boot --flake .#predator   # install the new generation
sudo reboot
```

At boot you should get **one** passphrase prompt and all volumes should mount.
After login, verify:

```bash
systemctl --failed
mount | grep -E '/games|/data'   # both present
cryptsetup status cryptgames; cryptsetup status cryptdata
```

If boot fails: pick the **previous generation** from the systemd-boot menu
(`timeout = 3`, `configurationLimit = 20`) — the keyfile slot is untouched, so
the old initrd still auto-unlocks. Re-diagnose before retrying.

## 4. Only after Step 3 succeeds — remove the keyfile keyslot + file

Find the keyfile's slot number in `luksDump`, or remove by keyfile:

```bash
sudo cryptsetup luksRemoveKey /dev/disk/by-uuid/9cb83a31-102e-440f-9fea-f6c86dbefea8 /etc/luks-keyfile
sudo cryptsetup luksRemoveKey /dev/disk/by-uuid/25748fb8-febe-42af-9a95-98980ca89751 /etc/luks-keyfile
sudo rm -f /etc/luks-keyfile
```

(The on-disk `/etc/luks-keyfile` lives on the encrypted root, so plain `rm` is
sufficient — there is no plaintext copy to shred.)

## 5. Finalize

```bash
cd /etc/nixos
sudo nixos-rebuild switch --flake .#predator
git add -A && git commit && git push   # keep the git generation in lockstep
```

## 6. Verify the gap is closed

```bash
# Only the passphrase slot remains on games + data:
sudo cryptsetup luksDump /dev/disk/by-uuid/9cb83a31-102e-440f-9fea-f6c86dbefea8 | sed -n '/Keyslots/,/Tokens/p'
sudo cryptsetup luksDump /dev/disk/by-uuid/25748fb8-febe-42af-9a95-98980ca89751 | sed -n '/Keyslots/,/Tokens/p'

# The new initrd carries no keyfile (search the unpacked cpio):
sudo lsinitrd /boot/EFI/nixos/*-initrd-*.efi 2>/dev/null | grep -i luks-keyfile && echo "STILL PRESENT" || echo "keyfile absent ✓"
# (If lsinitrd isn't available, unpack /boot's initrd with unzstd | cpio -t and grep.)
```

## Rollback summary

- Before Step 4: any failure → boot the previous generation; keyfile slot still
  works. No data at risk.
- After Step 4: if a later change breaks passphrase unlock, re-add a key with
  `sudo cryptsetup luksAddKey <dev>` from a working session or the installer USB
  (the passphrase still unlocks root, from which you can operate).
- The single passphrase always unlocks root, so you are never locked out as long
  as you know it.

## Notes

- **Do not remove `boot.initrd.kernelModules = [ "vmd" ]`.** systemd-initrd
  force-loads it for root discovery; without it the box can't find root.
- systemd-initrd is a *different* initrd implementation — the reboot in Step 3 is
  the real test. Keep the rescue USB handy until you've booted it successfully a
  couple of times.
