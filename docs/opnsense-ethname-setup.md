# OPNsense — deterministic USB-NIC naming via `ethname` (MAC pinning)

Runbook for the OPNsense box. Captures the hard-won setup so it survives a
disk loss or a rebuild. **Non-secret content only** — `/conf/config.xml`
holds secrets (WireGuard keys, passwords, certs) and must never be committed
here or to any unencrypted/pushed repo.

## The problem

OPNsense host: an ex-Chromebook (HP) running **OPNsense 26.1.6_2 amd64**
with MrChromebox UEFI (no per-device BIOS toggles — e.g. the integrated
webcam cannot be disabled in firmware). It has **no usable onboard NIC**;
networking is two **USB ethernet adapters**.

FreeBSD names USB NICs `ue0`/`ue1` by **enumeration order**, which is
non-deterministic across reboots. This was observed live: `ue0` and `ue1`
swapped which physical adapter they referred to between reboots.

OPNsense binds LAN/WAN to the interface **name** (`config.xml` has
`LAN = ue0`). So a reboot-time swap silently swaps **WAN ↔ LAN** — for a
firewall that is a security incident (rules apply to the wrong side; the
internal network can be bridged to the internet), not a cosmetic issue.
This was a hard blocker for using the box as a security edge router.

## Hardware (verified on the box)

| Role | Chipset | FreeBSD driver | MAC | Pinned name |
|------|---------|----------------|-----|-------------|
| LAN  | Realtek RTL8153 | `ure`  | `60:7d:09:8a:ad:f9` | `ue0` (serves `192.168.1.114/24`) |
| WAN  | ASIX AX88179    | `axge` | `9c:69:d3:18:a8:94` | `ue1` (future WAN) |

Both are top-tier FreeBSD-supported USB-ethernet chipsets.

## The fix: `ethname` + an OPNsense early syshook

`ethname` is a small FreeBSD `rc.d` interface-renamer that maps a device to
a fixed name by MAC. It runs `BEFORE: netif` and supports name *swapping*
(renames via temp names, so `ue0↔ue1` works). OPNsense configures
interfaces from its own bootup (not stock `netif`), so on OPNsense it must
be force-run from an `rc.syshook.d/early` hook — the OPNsense-documented
"run before network services" mechanism
(docs.opnsense.org/development/backend/autorun.html).

We pin the *names* `ue0`/`ue1` to MACs (not invent new names) so the
existing `config.xml` (`LAN = ue0`) stays valid and just becomes
deterministic — zero interface reassignment needed.

### Exact steps (as performed)

1. Install the package:
   ```
   pkg install -y ethname        # installed ethname-2.0.1 from the OPNsense repo
   ```
2. Create `/etc/rc.conf.d/ethname`:
   ```
   ethname_enable="NO"
   ethname_ue0_mac="60:7d:09:8a:ad:f9"
   ethname_ue1_mac="9c:69:d3:18:a8:94"
   ```
   `enable="NO"` deliberately: it must NOT run at the normal `netif` stage
   (too late on OPNsense). The early hook force-runs it with `onestart`.
3. Create the early hook `/usr/local/etc/rc.syshook.d/early/10-ethname`,
   mode `0755`:
   ```
   #!/bin/sh
   service ethname onestart
   ```
4. Validate the mapping **without rebooting** (dry run):
   ```
   service ethname onecheck
   ```
   Must report the intended MAC→name plan (e.g. "already named 'ue0'" for
   `60:7d…`, "already named 'ue1'" for `9c:69…`, or "Will rename …").
5. Reboot **at the physical console** (recovery needs it; see below).
   Allow 3–4 minutes — OPNsense boot is slow and the hook + USB
   enumeration add to it; a ping immediately after reboot will show 100%
   loss until it is fully up.
6. Verify from a LAN host:
   ```
   ssh root@192.168.1.114 'ifconfig ue0; echo ===; ifconfig ue1'
   ```
   Pass = `ue0` shows `ether 60:7d:09:8a:ad:f9` + `inet 192.168.1.114`,
   `ue1` shows `ether 9c:69:d3:18:a8:94`.
7. Reboot a second time and re-verify — the swap was intermittent, so
   determinism is only proven across multiple boots.

### Validation result

`onecheck` confirmed correct logic before any boot change. Two consecutive
reboots produced the **identical deterministic mapping**. Caveat: both
boots enumerated in the same order, so this proves "hook is safe + mapping
correct + no breakage", and relies on `ethname`'s upstream-proven
temp-name swap logic to correct a reversed enumeration if one occurs.

## Recovery / rollback

At the **physical OPNsense console** (SSH won't help if boot/interfaces
break):
```
rm /usr/local/etc/rc.syshook.d/early/10-ethname
reboot
```
Removes only the hook; OPNsense returns to stock (non-deterministic)
behaviour, nothing else changed. Full pre-work config restore point lives
on the box at `/conf/config.xml.pre-wan` (console menu `13) Restore a
backup`, or copy it back). OPNsense being down does **not** take home
internet down — it is currently a LAN peer; predator falls back to Quad9
(already configured in `modules/networking.nix`).

## OPNsense shell gotchas (learned the hard way)

The OPNsense **root shell is `tcsh`**, not bash/sh:

- `$(...)` → `Illegal variable name`. Use backticks or avoid.
- `>/dev/null 2>&1` / `2>&1` → `Ambiguous output redirect`. Use only `;`
  and pipes; no bash-style redirects. (`>`/`>>` single redirects are OK.)
- A literal `!` → history expansion `Event not found`, **even inside
  single quotes**. To write `#!/bin/sh`, build it without typing `!`:
  `printf '#\041/bin/sh\nservice ethname onestart\n' > <file>`
  (`\041` is octal for `!`).
- The OPNsense **console menu redraws on USB events** (e.g. the flapping
  internal webcam) and becomes hard to use. Run one-shot commands via
  non-interactive `ssh root@<ip> 'cmd; cmd'` (bypasses the menu). For an
  interactive shell, `ssh -t root@<ip> /bin/csh`.
- `service <name> onecheck|onestart` finds `/usr/local/etc/rc.d/<name>`
  and is shorter than the full path.

## Security / secrets

`/conf/config.xml` contains secrets. It is intentionally **not** in this
repo. This runbook is procedure + the two non-secret ethname files only.
A full encrypted OPNsense config backup (sops/age, private) is a separate,
future task — not in this (pushed) repo.

## Status & forward pointers

- ✅ **Step A complete** — deterministic USB-NIC naming, proven across
  reboots. The WAN/LAN-swap showstopper is resolved.
- ⏭ **Phase 1 (not done)** — assign `ue1` as WAN (DHCP) *behind the home
  router* (reversible validation). Requires moving OPNsense LAN off
  `192.168.1.114/24` to a non-conflicting subnet (e.g. `192.168.20.1/24`)
  with a test client; predator falls back to Quad9 meanwhile (already in
  `modules/networking.nix`). No predator repo change in Phase 1.
- ⏭ **Phase 2 (deferred, high blast radius)** — modem → OPNsense WAN
  (true edge router), home router demoted to AP. Requires coordinated
  `modules/networking.nix` edits on predator (default gateway + DNS, and
  the now-stale "OPNsense is a single-NIC LAN peer" comment block).
- ⏭ **Phase 3** — replace USB NICs with real hardware (the genuine
  long-term fix for a security-critical edge).
