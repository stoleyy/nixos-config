# Home-lab runbook

Operational reference for the predator + OPNsense LAN-host setup.
Future-you in 6 months: start here when something is broken.

## Topology

```mermaid
flowchart LR
  internet[Internet]
  router[Home router<br/>192.168.1.1<br/>does DHCP, NAT, port-forward<br/>UDP/51820 → .114]
  opnsense[OPNsense laptop<br/>ue0 = LAN = 192.168.1.114<br/>Unbound DoT + DNSBL<br/>WireGuard server<br/>NTP synced]
  predator[predator<br/>NixOS 25.11<br/>Wazuh manager+indexer+dashboard<br/>Wazuh agent — auditd]
  phone[Phone — WireGuard client<br/>10.99.0.2/32]

  internet <--> router
  router <--> opnsense
  router <--> predator
  phone -. WG over cellular .-> internet
  internet -. UDP/51820 .-> router
  router -. UDP/51820 .-> opnsense
  opnsense -. NAT-masq onto LAN .-> predator
```

- OPNsense is **not** a gateway. It's a LAN-host service appliance. The home
  router does the actual NAT/firewall for everything.
- Predator's NixOS pulls DNS from OPNsense Unbound via systemd-resolved.
- Wazuh agents on OPNsense and predator report to the manager on predator.
- Remote access: phone → cellular → home WAN IP (75.180.104.157) → router
  port-forward → OPNsense WireGuard → LAN.

---

## Troubleshooting trees

### "DNS is broken on predator"

1. **Confirm scope.** Is it predator-only, or does OPNsense itself also fail?
   - On predator: `host cloudflare.com 127.0.0.53` — is systemd-resolved alive?
   - On OPNsense: `drill cloudflare.com @127.0.0.1` — is Unbound resolving?
2. **predator side fails, OPNsense side works** → systemd-resolved is the
   culprit. `resolvectl status` should show `Current DNS Server: 192.168.1.114`
   on enp2s0 OR globally. If not: `services.resolved.extraConfig` in
   `modules/networking.nix` is the source of truth. Rebuild + restart resolved.
3. **OPNsense side also fails** → the issue is upstream or the box itself.
   - `ssh opnsense ping -c2 9.9.9.9` — is upstream reachable? If "No route to
     host" but the WAN gateway is the home router: stale ARP. `ssh opnsense
     arp -d 192.168.1.1` and retry.
   - `ssh opnsense ntpq -4 -p 127.0.0.1` — peers showing reach 0? Clock may
     have drifted; DNSSEC signatures will look invalid. Fix clock first.
   - `ssh opnsense pgrep -lf '/usr/local/sbin/unbound -c /var/unbound/'` —
     OPNsense's Unbound running? If `/usr/local/etc/...` shows instead,
     someone ran `service unbound onerestart` — see [[opnsense-unbound-gotchas]].

### "WireGuard isn't connecting from cellular"

1. **Server up?** `ssh opnsense wg show` — does wg0 exist + listen on port 51820?
   - No: `ssh opnsense configctl wireguard restart` ... well, that doesn't write
     wg0.conf. See [[wireguard-home]] — manual `wg syncconf wg0
     /usr/local/etc/wireguard/wg0.conf` is the workaround.
2. **Port-forward live?** From an external network: `nmap -sU -p 51820
   75.180.104.157` — open means port-forward works. Closed means router
   isn't forwarding.
3. **Public IP rotated?** `dig +short <ddns-hostname>` matches `ssh opnsense
   fetch -qo - https://ifconfig.me`? If not, DDNS update lagged or the client
   has a stale endpoint cached.
4. **Handshake but no traffic?** Check NAT outbound rule:
   `ssh opnsense pfctl -s nat | grep 10.99`. Should show
   `nat on ue0 inet from 10.99.0.0/24 to any -> (ue0:0)`. Missing = no LAN
   reachability for peers.

### "Wazuh agent shows disconnected in dashboard"

1. **Manager up?** `ssh predator podman ps | grep wazuh-manager`. If not:
   `journalctl -u podman-wazuh-manager --since '10 min ago'`.
2. **Indexer up + ready?** `podman exec wazuh-manager
   curl -sk -u admin:<pw> https://wazuh-indexer:9200/_cluster/health`.
   Wait ~30s after start; indexer is slow to come up.
3. **Network reachability from agent host:**
   - OPNsense: `ssh opnsense nc -zv <predator-LAN-IP> 1514` — UDP/1514 must
     resolve to "succeeded".
   - predator's own agent: container-to-container on podman network "wazuh".
4. **Certs match?** Reset certs only if you fully understand it — re-running
   `wazuh-certs-tool.sh` invalidates the existing trust chain.

### "DoT to Quad9 broken — Unbound returning SERVFAIL"

1. `ssh opnsense cat /var/unbound/etc/dot.conf` — should have
   `forward-tls-upstream: yes` and `forward-addr: 9.9.9.9@853#dns.quad9.net`.
   If only `@853` without `#dns.quad9.net`: `<type>` in `<OPNsense><wireguard>...<dots>...<dot>`
   XML is `forward` not `dot`. Edit XML, `configctl unbound restart`.
2. `ssh opnsense tcpdump -i ue0 -nn -c5 'host 9.9.9.9'` should show TCP/853
   traffic. If still UDP/53: see step 1.
3. **OISD blocklist breaking validation?** Disable temporarily via XML:
   set `<dnsbl>` to empty element, restart unbound. If validation comes back,
   the issue is in the python DNSBL module.

### "gaming-tuned boots to a black screen / TTY instead of Steam"

The `gaming-tuned` specialisation launches gamescope **standalone** via greetd
— no SDDM, no parent compositor. "Headless" here means gamescope never opens a
display and the boot drops to a bare console. **First read:**
`~/gamescope-session.log` — the session script (`packages/gamescope-session.nix`)
tees everything there and it survives reboots. The final
`steam-gamescope exited with code N` line is your entry point.

All four causes below are already fixed in-tree; this is the map for when a
driver / Steam / portal bump reintroduces one. They're in dependency order — a
failure at step N masks everything under it. **None of them are game-specific**
(there is no "Skyrim issue") — they're session-bringup failures that happen
before any game launches.

1. **Exits code 1 instantly, log barely past "Launching steam-gamescope".**
   A standalone gamescope has no compositor to nest in and needs a real KMS
   backend. Confirm `--backend drm` is still in
   `programs.steam.gamescopeSession.args` (`hosts/predator/default.nix`); pair
   it with `--prefer-output DP-2` + `--prefer-vk-device 10de:2786`. The NixOS
   module adds none of these. Foundational — without it nothing else matters.
2. **"failed to become DRM master" / libseat errors during handoff.**
   gamescope's libseat fallback chain (seatd → logind → builtin) can fail to
   acquire DRM master when systemd-logind owns the session. Force it:
   `LIBSEAT_BACKEND = "logind"` in the session `env` (`default.nix`).
3. **~120 s hang, *then* a drop to TTY — the headline failure.** Steam's CEF
   requests `org.freedesktop.portal.Desktop`; the gtk + kde portal backends try
   to activate, abort because no display exists yet (gamescope hasn't opened
   one — that needs Steam to launch first), the portal burns its 120 s
   activation timeout, Steam gives up, gamescope's primary child dies → TTY.
   Fix: `xdg.portal.enable = lib.mkForce false` (`default.nix`, commit
   `378f20e`). Steam then gets an instant `NameHasNoOwner` and takes a
   non-portal path (loses screencast / file-picker in Big Picture — fine for
   gaming). `journalctl -b -u xdg-desktop-portal` shows the activation storm if
   this regresses.
4. **"No provider of eglGetCurrentContext found" / Xwayland aborts — the
   Wayland + GPU one.** libepoxy 1.5.10 + NVIDIA 580.x: libepoxy's EGL resolver
   calls `eglGetCurrentContext` before any EGL context exists and aborts. Same
   root bug the Hyprland session dodges with `-glamor off`
   (`modules/hyprland.nix:10-19`), but gamescope spawns its **own** Xwayland
   from its closure and bypasses that wrapper — so the fix is env-side (commit
   `944316b`): `XWAYLAND_NO_GLAMOR=1` (the `-glamor off` equivalent) and
   `__EGL_VENDOR_LIBRARY_DIRS` in `default.nix`, plus an `LD_LIBRARY_PATH`
   prepend of libglvnd + `/run/opengl-driver/lib` in
   `packages/gamescope-session.nix` (libepoxy `dlopen`s `libEGL.so.1` with no
   RPATH, and RUNPATH isn't inherited by transitive dlopen). Revisit when
   libepoxy ≥ 1.5.11 or NVIDIA ≥ 590.

**Not a headless cause, but easy to conflate — low FPS once you're *in* a
game:** Proton/DXVK renders on the Intel iGPU instead of the RTX 4070 (commits
`9bce82d`, `44a972c`). Fixed by blacklisting `i915` (`modules/hardware.nix`),
`DXVK_FILTER_DEVICE_NAME = "NVIDIA"` (`modules/nvidia.nix`), and the
`--prefer-vk-device 10de:2786` from step 1. Symptom is bad framerate + low
`nvidia-smi` utilization, **not** a black screen — a different layer entirely.

> Perf footnote (not a boot failure): greetd doesn't grant `CAP_SYS_NICE`, so
> gamescope logs "falling back to regular-priority threads".
> `programs.steam.gamescope.capSysNice = true` (`modules/gaming.nix`) restores
> realtime scheduling.

---

## Update procedures

### OPNsense

- **DO NOT** auto-update. Plugin compatibility breaks subtly across major
  releases.
- Monthly cadence: log in, System → Firmware → Status, read the release notes
  *before* clicking "Update".
- Take a config backup (System → Configuration → Backups → "Download") right
  before pulling the trigger.
- After update: re-verify the Phase A+B+C checklist (DNS resolves with `ad`,
  WG handshake works, NTP synced).

### NixOS / predator

- Auto-builds weekly Sunday 04:00 (`system.autoUpgrade` in
  `modules/update-routines.nix`). Reboot is on you.
- Reboot to activate: `sudo systemctl reboot` after checking
  `nvd diff /run/booted-system /run/current-system` for surprises.
- Flake input bumps weekly Sunday 03:00 via the `flake-lock-update` timer.
  Manually `git diff flake.lock` after, commit if happy.

### Wazuh

- Version pinned in `modules/wazuh-manager.nix` (single `let` binding).
- Bump only when 4.X+1 ships and you've read the upstream migration notes.
- Containers re-pull on next `podman-wazuh-*.service` restart.

---

## Backup / restore

### OPNsense config

- Auto-backup destination: **TODO** (configure in System → Configuration →
  Backups → choose Nextcloud / SCP / Google Drive).
- Restore: System → Configuration → Backups → "Restore" → pick file.
  Reboots automatically.

### Wazuh data (indexer state)

- Live state in `/var/lib/wazuh-stack/{manager,indexer}` on predator.
- **TODO**: Restic backup of these paths to Backblaze B2 (Tier 3.3 in plan).

### Predator NixOS config

- Repo: <https://github.com/stoleyy/nixos-config>.
- `git push` to origin pushes the source of truth.
- `/etc/nixos` is a checkout; reinstall procedure pulls main and rebuilds.

---

## Password recovery

### OPNsense admin

- Boot OPNsense in single-user mode (select option from boot menu).
- `mount -uw /` then `pw usermod root -h 0` and re-set the password.

### Wazuh admin

- Stop the indexer container, edit `/var/lib/wazuh-stack/indexer/.../internal_users.yml`,
  reset the bcrypt hash. Documented at <https://documentation.wazuh.com/current/user-manual/user-administration/password-management.html>.

### sops age key

- Stored at `/var/lib/sops-nix/key.txt` on predator.
- **Back this up offline.** Losing it locks all sops-encrypted secrets out
  of the rebuild. Suggested: print, store in a fireproof safe.

---

## Useful commands

```
# DNS path verification
drill -D cloudflare.com @192.168.1.114      # AD flag = OPNsense validating
drill pagead2.googlesyndication.com @192.168.1.114  # NXDOMAIN = OISD blocking

# WG state
ssh opnsense wg show                         # peer handshakes, transfer counts
ssh opnsense sockstat -4 -l | grep 51820

# Wazuh state
ssh predator podman ps                       # all containers running
ssh predator podman logs --tail 50 wazuh-manager

# NTP sync
ssh opnsense ntpq -4 -p 127.0.0.1            # need * or + in selection column

# Routing sanity
ssh opnsense netstat -rn -f inet | head -5   # default → 192.168.1.1

# Audit events flowing
sudo journalctl -u audit --since '1 hour ago' | head
sudo ausearch -k identity --start recent      # auth-state changes
```

---

## Architecture quirks worth knowing

(See memory files for the full breakdown — this is the cliff-notes.)

- **OPNsense has ONE NIC** (USB ethernet `ue0`). Cannot be inline router/IPS.
- **OPNsense regenerates `/var/unbound/etc/`** on every `configctl unbound
  restart`. Durable Unbound config tweaks must go in
  `/usr/local/etc/unbound.opnsense.d/zz-*.conf` (survives regen) or via GUI.
- **Two unbound binaries exist** — never run `service unbound restart` on
  OPNsense; it kills the OPNsense-managed daemon. Always `configctl unbound restart`.
- **WireGuard wg0.conf isn't auto-written** by OPNsense's wg-service-control.php
  when the server entry was created via XML edit. Manual `wg syncconf` after
  template populates volatile fields.
- **/etc/nixos is the deploy point**, but the canonical source is the GitHub
  repo. Edits to `/etc/nixos` files are lost on next `git pull origin main`.
- **NixOS modules go in `lib/default.nix`**, not `flake.nix`.
