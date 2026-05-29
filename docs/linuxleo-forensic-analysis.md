# LinuxLEO 4.98 → forensic-resistance review of `predator`

**Question asked:** does *LinuxLEO 4.98* ("The Law Enforcement and Forensic
Examiner's Introduction to Linux", Barry J. Grundy,
<https://linuxleo.com/Docs/LinuxLEO_4.98.pdf>) imply any changes or
optimizations for this NixOS config's security?

**Short answer:** yes, but modestly — and mostly it *validates* what's already
here. The document is a **dead-box (powered-off disk) examiner's primer**. Every
recovery technique it teaches assumes an **unencrypted** disk, and the one
defense it repeatedly names is full-disk encryption — which this host already
implements well. Mapping its workflow onto this specific config surfaces exactly
one materially useful change (a `/boot` keyfile exposure) plus one optional
hardening add (a host integrity baseline), and it argues *against* one thing a
naive hardening pass would add (secure-delete tooling).

---

## What the document actually covers

It is a manual for *examining* a seized Linux disk, not for defending one:

- **Dead-box imaging** (`dd`, `dc3dd`, `dcfldd`, `ewfacquire`): bit-for-bit
  copies including slack + unallocated. Explicitly warns that read-only mounts
  can't be fully trusted — assume a powered-off disk is imaged in full.
- **Deleted-file recovery / carving / slack / unallocated** (Sleuth Kit `fls`,
  `icat`, `blkcat`; `scalpel`, `photorec`): extensive. Notes ext4 clears an
  inode's direct block pointers on delete (so recovery falls back to carving —
  a *marginal* obstacle, not prevention).
- **Filesystem metadata & timelines**: MAC times (`istat`/`mactime`) are
  preserved even for deleted inodes; full timeline reconstruction is possible.
- **Hashing / integrity** (`md5sum`, `sha256sum`): verification of acquired
  images — *integrity*, never *confidentiality*. Hashing cannot hide content.
- **Artifacts**: `.bash_history`, `/var/log`, and swap are called out as
  recoverable evidence.
- **Encryption**: covered only briefly, and definitively — an encrypted volume
  without the passphrase is **unrecoverable**. This is the only artifact class
  the document treats as fully protected.
- **SSD / TRIM**: acknowledged as out of scope but noted to make deleted-data
  recovery much harder ("Deterministic read data after TRIM").
- **NOT covered**: live/memory (RAM) acquisition, and anti-forensics
  (secure deletion, log scrubbing) beyond wiping a *destination* disk.

## Recoverable artifact → is it neutralized here?

| Examiner can recover (unencrypted disk) | Neutralized on `predator`? | By what |
|---|---|---|
| Allocated file contents | ✅ at rest | LUKS2/AES-256-XTS FDE on `/`, games, data |
| Deleted files / slack / unallocated | ✅ at rest | FDE (ciphertext only without the key) |
| MAC-time timelines | ✅ at rest | FDE; `noatime` on `/` also drops one artifact |
| `.bash_history`, `/var/log` | ✅ at rest | On the passphrase-protected encrypted root |
| Swap contents | ✅ | Swapfile on encrypted root + volatile zram; no hibernation |
| Encrypted volume w/o key | ✅ by design | The document's own stated limit |

So against this document's threat model, the box is already in the strongest
position it recognizes. Verified in `hosts/predator/hardware-configuration.nix`,
`hosts/predator/default.nix`, `modules/hardware.nix` (zram), `modules/system.nix`
(tmpfs `/tmp`, coredumps off), `modules/hardening.nix` (firewire/thunderbolt DMA
modules blacklisted), and the migration spec
`docs/superpowers/specs/2026-05-26-luks-migration-design.md` (status *Approved*:
LUKS2, AES-256-XTS, argon2id KDF).

---

## The one materially useful finding

`hosts/predator/hardware-configuration.nix` uses `boot.initrd.secrets` to bake
`/luks-keyfile` into the **initramfs**, which lives on the **unencrypted `/boot`
ESP**. The migration spec describes the keyfile as "on encrypted root," which
understates the at-rest reality: a copy rides in the initrd on the one
unencrypted partition.

Because a dead-box image includes `/boot`, an examiner can unpack the initrd
cpio, read `/luks-keyfile`, and **decrypt `/games` and `/data` with no
passphrase**. Only root (which holds `/home/stoleyy` — browser profiles, GPG,
dotfiles) is genuinely passphrase-protected. `/data` holds backups/archives, so
this is the partition where the gap matters most.

**Fix (chosen direction): drop the keyfile, single-passphrase unlock.** The same
passphrase is already enrolled in all three LUKS keyslots (migration spec Phase
3), so switching to systemd-initrd (which caches and retries the entered
passphrase across devices) yields one prompt, all three volumes, and **no key
material on `/boot` at all**. This requires interactive on-box steps and a reboot
test → see **`docs/luks-passphrase-unlock-runbook.md`**.

## Optional add (implemented): host integrity baseline

The document's hashing/integrity theme, flipped to the defender: a cryptographic
baseline that detects tampering — including evil-maid edits to the unencrypted
`/boot`. `modules/aide.nix` adds an AIDE baseline + daily check over
`/boot`, `/etc`, `/root`, and key user dotfiles (Wazuh FIM remains the intended
long-term mechanism but is blocked on manager/cert bootstrap). Alerts go to the
journal (captured by the Vector pipeline) and a desktop notification.

## What the document tells us NOT to add

**Secure-delete / `shred` tooling.** A codebase scan flagged its absence as a
"gap," but the document's SSD/TRIM section settles it: on NVMe, wear-leveling
remaps blocks so `shred` cannot reliably overwrite the original cells, and with
FDE the data is already ciphertext. The correct SSD anti-forensic posture is
exactly what's configured: FDE + `allowDiscards=true` + `services.fstrim`. Adding
`shred`/`srm` would be cargo-cult, not hardening. The `allowDiscards` metadata
trade-off was already weighed and accepted in the migration spec.

## Out of scope of this document (not pursued here)

Kernel lockdown and `/proc` hidepid relate to **live/memory** forensics, which
LinuxLEO explicitly does not cover. Lockdown additionally risks the proprietary
NVIDIA module on this box. These may be worth revisiting under a different
threat model, but nothing in *this* document motivates them.

---

*Sources: LinuxLEO 4.98 (full PDF analysis), and the live config files cited
above. This review is documentation only; the actionable changes are
`modules/aide.nix` and the runbook.*
