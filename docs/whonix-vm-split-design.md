# Whonix-style VM split — design & feasibility gate

Goal: **true Whonix-grade isolation** on `predator` — a Tor **gateway VM** plus a
**workstation VM** whose *only* network path is the gateway, so that even a full
compromise of the workstation cannot discover the real IP or bypass Tor.
"Usable": single-player gaming, browsing, and media keep working (no multiplayer,
mic, or webcam, so the usual blockers don't apply).

> Status: **design + feasibility gate only.** No host config is changed by this
> PR. The build is hardware-gated (GPU passthrough) and proceeds in stages once
> the on-box facts below are confirmed.

## The isolation guarantee (what makes it "Whonix", not just "Tor on")

The workstation VM has **no NIC to the outside** — only a virtual link to the
gateway. Tor runs on the **gateway**, which the workstation cannot reconfigure.
Therefore a malware/root compromise *inside* the workstation has no route to leak
the real IP. This is the property a single-OS transparent-Tor setup does **not**
give you, and it's why you picked this path.

## Routing policy — VPN-first, Tor only where it matters

Refinement: *"everything that makes sense to be on VPN, could be."* Tor only
benefits traffic that is **genuinely anonymous AND not tied to your identity**.
Everything you're logged into, or that's bandwidth-heavy, belongs on the VPN —
Tor adds nothing there but pain.

| Traffic | Lane | Why |
|---|---|---|
| Steam, qBittorrent, game downloads | **VPN** | Torrents deanonymize over Tor (BT/DHT leaks your IP) + abuse the network; Steam is logged-in |
| Logged-in / identity services — Proton, Brave Sync, Discord, Spotify, Google, **banking/vault** | **VPN** | The login already identifies you; Tor hides nothing it doesn't already know |
| Media stack (Jellyfin, *arr) | **VPN** | Indexer/tracker traffic, already VPN-bound |
| System updates — nix substituters, flake bump, fwupd | **VPN** | Bulk; the CDN sees it anyway; Tor is glacial |
| Personal daily browsing (logged-in, YouTube/social) | **VPN** | Identity-linked regardless |
| Untrusted / disposable browsing, anonymous research (**not** logged in) | **Tor** | The only traffic that truly gains from anonymity |
| Unclassified / new outbound | default | Recommend **Tor** (fail-toward-anonymity); flip to VPN for max usability |

## Architecture: this refinement points to a *lighter* build

- **Option A — full VM split** (detailed below): the entire workstation *incl.
  gaming* runs in a VM behind the gateways, RTX 4070 via VFIO. Justified **only**
  if you want your *whole* daily workload switchable to Tor isolation. Under the
  VPN-first policy above, this is heavy and carries the GPU-passthrough risk for
  little gain.
- **Option B — VPN'd daily driver + a dedicated Tor anon VM (RECOMMENDED).** Keep
  `predator` as your hardened, VPN'd gaming daily driver (PRs #59/#60). Add **one**
  lightweight guest: a true Whonix-Workstation (browser-only, virtio-gpu, **no GPU
  passthrough**) with **no non-Tor route**, for anonymous activity. The anon
  workload gets real Whonix isolation; gaming/identity stays fast on VPN.

  This is the "Whonix VMs alongside" option you *didn't* pick earlier — but that
  was when the goal was "every packet from this machine anonymous." Your VPN-first
  steer consciously relaxes that, which makes Option B the correct, far-cheaper
  choice (no display/GPU surgery, no re-architecting the desktop into a VM).

The full-split topology below is retained as **Option A** reference.

## Network topology (incl. the gaming-download exception)

```
                              ┌────────────────────────────────────────────┐
  physical NIC ── HOST (thin hypervisor) ── ProtonVPN (wg, kill switch) ────┼──▶ internet
                    │                                                       │
                    │  (host does NO interactive networking)                │
                    ├──────────────┬────────────────────────────────────────┘
                    ▼              ▼
            ┌───────────────┐   (VPN-exit path, NAT to host VPN)
            │  sys-tor VM   │              │
            │  (gateway)    │              │
            │  Tor + nft    │              │
            │  fail-closed  │              │
            └──────┬────────┘              │
            net0 (Tor) │                   │ net1 (VPN, NO Tor)
                       ▼                   ▼
                 ┌─────────────────────────────────┐
                 │        WORKSTATION VM            │
                 │  default route → net0 (Tor)      │
                 │  qBittorrent + Steam → net1 (VPN)│  ◀── the exception
                 │  RTX 4070 (VFIO passthrough)     │
                 │  desktop / browser / games       │
                 └─────────────────────────────────┘
```

- **Everything defaults through Tor** (`net0` → sys-tor). Tor-over-VPN: the host's
  ProtonVPN is the underlay, so the ISP sees only WireGuard, never Tor.
- **qBittorrent + Steam (gaming downloads) ride `net1`** → straight to the host's
  ProtonVPN, **bypassing Tor**. Realized inside the workstation with policy
  routing + cgroup/UID marking (same idea as today's `untrusted` GID + the
  qBittorrent interface bind), so only those apps take the VPN path.
- **Deliberate trade-off:** `net1` is a non-Tor route, so the workstation is not
  *fully* sealed — but it carries only torrent/Steam traffic, which is correct on
  a VPN and pointless/harmful on Tor (see rationale above). If you ever want zero
  non-Tor routes, move qBittorrent + Steam into a **separate downloader VM** on
  the VPN path and share the games volume to it (stricter, more moving parts).

## ⛔ Feasibility gate — the GPU (Option A only)

> **Option B skips this entirely** — the anon VM is browser-only (virtio-gpu /
> software rendering), so no GPU passthrough is needed. This gate applies only if
> you choose the full VM split (Option A).

`predator` has **one** GPU (RTX 4070) driving your only display (DP-2), and the
iGPU is **blacklisted** (`modules/hardware.nix`). VFIO passthrough needs the host
to relinquish the 4070 to the workstation VM, which means the host needs a
*different* display path. Decision:

- **Recommended — enable the iGPU for the host.** Un-blacklist `i915`, enable
  "iGPU Multi-Monitor" / set iGPU as primary in BIOS, bind the 4070 to
  `vfio-pci`. Host runs **headless** (or on the iGPU); the workstation VM owns the
  4070 and drives the physical monitor on DP-2. Clean, no GPU-reset gymnastics.
- **Alternative — single-GPU passthrough.** Host tears down its console, hands the
  4070 to the VM on launch, reclaims on shutdown. No iGPU needed, but fragile
  (NVIDIA reset, no host GUI while gaming).

### Run these on the box and paste the output — I build Stage 2+ from them

```bash
# 1. Is VT-d/IOMMU on? (need it before anything)
#    Temporarily add  intel_iommu=on iommu=pt  to kernelParams, rebuild, reboot, then:
dmesg | grep -e DMAR -e IOMMU | head

# 2. IOMMU groups — the 4070 (+ its HDMI-audio function) MUST be isolated
for g in /sys/kernel/iommu_groups/*; do
  echo "Group ${g##*/}:"; for d in "$g"/devices/*; do echo "  $(lspci -nns "${d##*/}")"; done
done | grep -A2 -iE "vga|nvidia|audio"

# 3. Exact PCI IDs of the 4070 + its audio function (for vfio-pci.ids=)
lspci -nnk | grep -A3 -iE "nvidia|vga"

# 4. Can the iGPU be enabled? (BIOS) — does UHD 770 show up?
lspci -nn | grep -i "VGA\|Display"
```

**Gate:** if the 4070 (and its audio function) are **alone** in their IOMMU group →
clean passthrough. If they share a group with other devices → we'd need an ACS
override (messy, weakens isolation) or it's a no-go.

## Storage

- Games volume (`/home/stoleyy/games`, 1.5 TiB): pass the whole partition to the
  workstation VM (virtio-blk) or share via virtio-fs. Keep LUKS — opened in the
  workstation, key never on the gateway.
- `/data`: stays on the host (or shared read-only).

## Flake re-architecture

Today's single `predator` config splits into three:

- **`hosts/predator-host/`** — thin hypervisor: boot, LUKS, IOMMU/VFIO, ProtonVPN
  underlay, `libvirtd` (or `microvm.nix`), the two internal networks. Minimal
  packages. No desktop.
- **`hosts/sys-tor/`** — tiny NixOS guest: Tor (TransPort + DNSPort), nftables
  fail-closed, two NICs (uplink to host→VPN, downlink to workstation). No state.
- **`hosts/workstation/`** — inherits **most of today's config**: Hyprland/Plasma,
  gaming, Brave compartments, the game-install pipeline, theming, all of
  `home/stoleyy`. Gets the 4070 via VFIO; default route = sys-tor; qBit/Steam → VPN.

`lib/mkHost` grows to build all three; `home-manager` moves under the workstation.

## Staged rollout (each stage is reversible / testable)

1. **IOMMU enable + verify** (above). Feasibility gate. *(host kernelParam, reversible)*
2. **iGPU for host + bind 4070 to vfio-pci.** Host headless on iGPU. *(display reshuffle — have a recovery generation ready)*
3. **sys-tor gateway VM** (libvirt/microvm): Tor + fail-closed nft, internal net. Verify it Tor-routes a test guest.
4. **workstation VM** skeleton: boots, gets 4070 passthrough, default route via sys-tor. Verify `check.torproject.org` says "yes" and there is **no** non-Tor route except `net1`.
5. **Migrate the desktop** (Hyprland, gaming, browser, home-manager) into the workstation; strip the host.
6. **Wire the gaming-download exception**: `net1` → VPN, policy-route qBit + Steam onto it. Leak-test: confirm only those apps use `net1`, everything else is Tor.
7. **Leak validation**: from inside the workstation, attempt to reach the internet with Tor down → must fail closed; DNS must resolve only via Tor.

## Honest limits (so the goal stays grounded)

- **The gaming-download path is a real non-Tor channel** by your choice — correct
  for torrents/Steam, but it means the workstation isn't 100% sealed.
- **Steam / Brave Sync / Proton remain identity anchors** — Tor hides IPs, not
  logins. Anonymous activity must use the un-logged-in, Tor-only side.
- **GPU passthrough is the hard part** and is unverifiable from CI — it lives or
  dies on the IOMMU-group output above, and on NVIDIA reset behavior (Ada is
  generally well-behaved).
- **Single-display constraint**: while the workstation VM holds the 4070, the host
  has no GUI on DP-2 — manage it via TTY/serial/SSH-over-the-internal-net.
- **Timing correlation / always-on persistence** remain (a VM split doesn't fix a
  global passive adversary or behavioral fingerprint; Tails-style amnesia would).
