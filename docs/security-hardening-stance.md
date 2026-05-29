# Security hardening stance — `predator`

Living audit of the residual security weakpoints after the network-obfuscation +
detection wave (PR #59), and the hardening applied on top of it. This is the
"stance" document: what's defended, what's an accepted trade-off, and the
roadmap for the architectural gaps.

## Threat model

Single-user bare-metal desktop that **routinely executes pirated game binaries**
(FitGirl/DODI repacks via Wine, launched through Steam) and does
compartmentalized browsing. Normal-home physical security. No inbound services
(no sshd; media/web UIs are localhost-only behind a default-deny firewall). All
egress is forced through ProtonVPN (fail-closed kill switch).

The dominant risk is therefore **untrusted code running at full user privilege**,
not network intrusion. Qubes' core promise — compromise of one domain cannot
reach another — is only partially met, because every "domain" shares one UID
(`stoleyy`) and `$HOME`.

## Risk heatmap (Likelihood × Impact)

| Impact ↓ \ Likelihood → | Low | Medium | High |
|---|---|---|---|
| **Critical** | 🟠 W5 evil-maid / boot | 🟠 W2 same-UID blast radius (browser FS-jailed) | 🔴 W1 pirated-game execution |
| **High** | 🟡 W8 disko DR drift | 🟠 W6 supply chain · 🟠 W7 user→root | 🔴 W3 gaming-mode blackout |
| **Moderate** | 🟢 W9 LAN services | — | 🟠 W4 detect-without-alert |
| **Low** | — | — | — |

🔴 act first · 🟠 plan it · 🟡 latent footgun · 🟢 acceptable

## Weakpoint register

| ID | Weakpoint | L×I | Status | Notes |
|---|---|---|---|---|
| **W1** | Pirated game binaries run at full user privilege (Wine/Steam as `stoleyy`) | H×C 🔴 | **OPEN** — roadmap below | Highest-likelihood path to total user compromise |
| **W2** | All trust domains share one UID + `$HOME` (Brave profiles, KeePassXC, keys) | M×C 🔴→🟠 | **PARTIAL** — browser FS-jailed | Each Brave domain now runs in a bubblewrap tmpfs-`$HOME` jail (`home/stoleyy/browser.nix`): a browser RCE can no longer read sibling profiles, `~/.ssh`, `~/.gnupg`, or the KeePassXC `.kdbx`. Untrusted/disposable additionally get NO path to the password manager. Residual: a malicious *game* (W1) still runs as `stoleyy` and crosses everything |
| **W3** | Gaming session shed AppArmor + auditd + IDS while running the most untrusted code | H×H 🔴 | **HARDENED** | AppArmor + auditd now kept ON in `gaming-tuned`; only the heavy net/log monitors stay shed |
| **W4** | Detection recorded but nobody alerted (auditd/Suricata/CrowdSec on; sinks off) | H×M 🟠 | **HARDENED** | Loopback `ntfy-sh` enabled + `OnFailure` wired to VPN/DNS/Suricata/CrowdSec |
| **W5** | Evil-maid: unencrypted `/boot`, no Secure Boot, unmeasured initrd, secondary-disk LUKS keyfile in initrd | L×C 🟠 | **ACCEPTED** | Low likelihood at home; Secure Boot bricked the box twice (lanzaboote disabled). Re-attempt deliberately, out of band |
| **W6** | Supply chain: weekly auto `flake update` + broad `nix-ld` foreign-ELF surface | M×H 🟠 | **ACCEPTED** | Auto-update is a deliberate "hands-off" choice; `autoUpgrade` is build-only (no auto-switch). Review flake bumps if paranoia rises |
| **W7** | User→root privesc after a user-level compromise (sudo phish/keylog) | M×H 🟠 | **PARTIAL** | sudo already requires a password + `execWheelOnly`; mostly downstream of W1/W2 |
| **W8** | `disko.nix` provisioned plain ext4 — DR reinstall would be unencrypted | L×H 🟡 | **HARDENED** | disko spec now wraps root/games/data in LUKS, mirroring the live layout |
| **W9** | LAN-exposed services (avahi mDNS, KDE Connect, Steam Remote Play) | L×M 🟢 | **ACCEPTED** | Deliberate usability features; close them if unused |

## qBittorrent automation (deep-dive on W1's trigger)

The `game-install` pipeline (`packages/game-install.nix`), wired via qBittorrent's
"Run external program on completion", is the concrete mechanism behind W1. It
auto-runs `wine setup.exe /SILENT /SUPPRESSMSGBOXES` on completed torrents.

| ID | Finding | Severity | Status |
|---|---|---|---|
| **Q1** | Fully automated, **silent, unattended execution of untrusted Windows installers** on every torrent completion — no confirmation, no signature/AV check, no allowlist | 🔴 | OPEN (roadmap) |
| **Q2** | **Privilege mismatch.** The hardened `qbittorrent` *system* service cannot actually run the pipeline: `MemoryDenyWriteExecute=true` breaks Wine's W^X, `ProtectSystem=strict` + `ReadWritePaths` exclude `/home/stoleyy/games` (only `…/games/media`), and there is no Steam `userdata` under the `qbittorrent` user. So the documented automation must run as **`stoleyy`** (full privilege) — the W1 path in full — *or* it is silently broken. | 🔴 | DOCUMENTED |
| **Q3** | The "run external program" string is an **RCE primitive stored in mutable state** (`/var/lib/qbittorrent`), not declarative, and is reachable through the WebUI | 🟠 | MITIGATED (WebUI → loopback + Host-header validation) |
| **Q4** | Torrent name → `INSTALL_DIR="$GAMES_DIR/$GAME_NAME"` was **not path-sanitized** (traversal via `/` or `..`); the "largest `.exe`" is then executed | 🟡 | HARDENED (name now stripped of `/`, `..`, leading dots) |
| **Q5** | WebUI password not set declaratively (relies on qBittorrent's first-run random) | 🟢 | MITIGATED (loopback-bound; not remotely reachable) |

**What's solid:** qBittorrent is interface-bound to `protonvpn`, `bindsTo` the VPN
unit (dies if the tunnel drops — no leak), DHT/PeX/LSD disabled, `openFirewall =
false`, and the service carries the full systemd sandbox.

**The headline:** the hardened service and the documented automation are mutually
inconsistent — which strongly implies the install runs as `stoleyy`. The correct
fix is **not** to relax the sandbox to permit Wine (wrong direction); it is to run
the installer + game under a **dedicated confined UID** (W1 roadmap) or, as an
interim, `firejail --private` the Wine step so a malicious installer can't read
`stoleyy`'s `$HOME` (browser profiles, KeePassXC `.kdbx`, SSH/GPG keys).

## Already-strong (green — don't re-spend effort)

Encrypted + anonymized DNS · MAC/hostname/IPv6 privacy · ProtonVPN fail-closed
kill switch · no inbound SSH + default-deny firewall · KSPP/CIS kernel hardening
(+ max mmap ASLR entropy) · USBGuard allowlist · KeePassXC `firejail --net=none` ·
WebRTC leak closed (`disable_non_proxied_udp`) · per-domain bubblewrap browser
FS-jail (masks keys + sibling profiles) · `untrusted` + `vault` GID LAN-block ·
Tor egress for untrusted/disposable · scoped graphene-hardened-malloc (browser) ·
auditd/Suricata/CrowdSec/vector enabled.

## Roadmap for the 🔴 architectural cluster (W1 + W2)

**Update:** W2's *browser* vector is now closed by the per-domain bubblewrap
FS-jail (`home/stoleyy/browser.nix`) — a browser RCE can no longer read across
domains or steal `~/.ssh`/`~/.gnupg`/the `.kdbx`. What remains of the hot cluster
is the **games (W1)** path: pirated binaries still run as `stoleyy` with full
`$HOME` access. The only thing that meaningfully shrinks *that* is a **real
privilege boundary** under the games. Options, least → most isolation:

1. **Dedicated low-privilege `gamer` UID** (recommended first step). Games + the
   `game-install` Wine step run as `gamer`, whose home is the games volume and
   which has **no read access** to `stoleyy`'s `$HOME` (browser profiles,
   KeePassXC `.kdbx`, SSH/GPG keys). Needs: `gamer` in `video`/`render`/`audio`/
   `gamemode`, a `loginctl`/greetd seat for the gaming session, Steam + the
   shortcut pipeline rewired to that UID. Medium effort, large blast-radius
   reduction. Cannot be validated in CI (needs the real gaming session) — stage
   behind a specialisation and test on-box.
2. **`firejail --private` the install + launch path** as an interim: confine the
   Wine installer and the game so they can't read the rest of `$HOME`. Lighter,
   but Steam/Proton confinement is finicky.
3. **`microvm.nix` guest** for the highest-value zone (vault browsing + keys) or,
   inversely, for the games. True VM boundary — closest to Qubes — but the
   heaviest change (GPU passthrough/virgl, separate Nix closure).

The browser window-frame colors now carry a real filesystem boundary (the bwrap
jail), not just a label. The **games** path remains unconfined until one of the
above lands — treat a running game as fully trusted (see CLAUDE.md pitfall).

## Validation status

Everything except Suricata's build-time config check was validated by a full
`toplevel.drvPath` eval+IFD (Suricata is uncached for the pinned nixpkgs rev and
its source build pulls `valkey`, which doesn't compile in the CI/web sandbox; it
builds on real hardware). Always run the ladder before `switch`:

```
nix flake check --no-build
nixos-rebuild dry-build --flake .#predator   # Suricata compiles from source here
sudo nixos-rebuild test --flake .#predator    # reversible by reboot
systemctl --failed && journalctl -p err -b 0
sudo nixos-rebuild switch --flake .#predator
```
