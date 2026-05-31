# Android Emulator Module — Design Spec

**Date:** 2026-05-30
**Status:** Approved
**Module:** `modules/android-emulator.nix`
**Gate:** `modules.androidEmulator.enable` (default `false`)

## Purpose

Provide a secure, anonymous Android emulator for GPS spoofing research.
The VM must be indistinguishable from a real mobile device to any app or
service inspecting its identity, and its network traffic must be
geographically consistent with the spoofed GPS location.

## Non-Goals

- GPU passthrough (software rendering via virtio-gpu is sufficient)
- Google Play Services (tracking beacon — excluded by design)
- Production mobile use (this is a research tool)
- Protecting against host-level compromise (if host is owned, VM is transparent)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Host (NixOS)                                        │
│                                                     │
│  ┌──────────────┐   NMEA via      ┌──────────────┐  │
│  │ gpsd / helper │──virtio-serial──│ Android-x86  │  │
│  │ (GPS feed)   │   (host→guest)  │ VM (QEMU/KVM)│  │
│  └──────────────┘                 │              │  │
│                                   │ mock location│  │
│                                   │ app reads    │  │
│  ┌──────────────┐   virbr-android │ NMEA stream  │  │
│  │ nftables     │◄───NAT bridge───│              │  │
│  │ kill switch  │                 └──────────────┘  │
│  └──────┬───────┘                                   │
│         │ forward only to protonvpn (VM peer)       │
│         ▼                                           │
│  ┌──────────────┐                                   │
│  │ wg-quick     │  ← separate Proton server from    │
│  │ (VM peer)    │    host tunnel                     │
│  └──────────────┘                                   │
└─────────────────────────────────────────────────────┘
```

## Components

### 1. Virtualization Layer

- **libvirt + QEMU/KVM** — managed VM lifecycle
- `stoleyy` added to `libvirtd` group
- VM resources: 4 vCPU, 4 GB RAM
- Devices: virtio-gpu, virtio-net, virtio-serial (GPS channel)
- No USB passthrough, no clipboard bridge, no spice agent, no shared filesystem
- Disk: `~/android-emulator/android.qcow2` (user-managed, not in /nix/store)
- ISO: `~/android-emulator/android-x86.iso` (user downloads manually)
- AppArmor/seccomp on QEMU process (libvirt default)

### 2. Network Isolation & VPN Routing

- Dedicated libvirt network `android-vpn` on bridge `virbr-android`
- Subnet: `10.71.0.0/24` (VM gets `10.71.0.2`, gateway `10.71.0.1`)
- NAT forwarding exclusively through the `protonvpn` WireGuard interface
- nftables kill switch: if `protonvpn` interface is down, all VM traffic is dropped
- **Separate VPN peer:** a second WireGuard interface (`protonvpn-android`) carries VM traffic to a geo-matched Proton server, independent of the host's `protonvpn` tunnel. This prevents exit-IP correlation between host and VM
- DNS: Android's private DNS setting pointed at a resolver geographically consistent with the spoofed location (set by profile script)
- No IPv6 (matches host config)

### 3. GPS Simulation Toolkit

**NMEA feed via virtio-serial (host → guest only):**

- Host-side: helper script generates NMEA 0183 sentences (GGA, RMC, GSV) and writes to the virtio-serial chardev
- Guest-side: mock location app (e.g., FakeGPS or custom) reads `/dev/ttyS1` for NMEA stream
- Supports: latitude, longitude, altitude, speed, heading, satellite count, HDOP
- Route replay: feed a GPX file to simulate movement along a path

**Helper script `android-emu-gps`:**

```
android-emu-gps --profile tokyo     # preset: coords + VPN + tz + locale + DNS
android-emu-gps --lat 35.6762 --lon 139.6503 --alt 40
android-emu-gps --gpx route.gpx     # replay a recorded route
android-emu-gps --speed 1.4         # walking speed (m/s)
android-emu-gps --list-profiles     # show available location profiles
```

Profile sets ALL of:
- GPS coordinates (NMEA feed)
- Proton VPN server (geographically matching region)
- Android timezone (`Asia/Tokyo`)
- Android locale (`ja_JP` or configurable)
- DNS resolver (region-appropriate public resolver)
- Advertising ID randomization

### 4. Device Identity — Medtronic CardioSync Stent

The VM masquerades as an FDA-cleared cardiac stent monitor. All `build.prop`
values are overridden to present a consistent medical device identity:

```properties
ro.product.manufacturer=Medtronic
ro.product.model=CardioSync™ Stent Monitor v3.7
ro.product.device=implant-unit-0x4F2A
ro.product.brand=Medtronic Cardiac Solutions
ro.build.display.id=STENT-OS 2.1.4 / FDA-510(k) K247831 / REL-KEYS
ro.build.description=cardiosync-monitor userdebug 14 STENT.240301.007 release-keys
ro.build.fingerprint=Medtronic/CardioSync/implant-unit-0x4F2A:14/STENT.240301.007/release-keys
ro.hardware=biotelemetry-soc
ro.serialno=MDT-IMPLANT-2024-8837201
ro.product.board=titanium-mesh-rv2
gsm.operator.alpha=Medtronic BodyNet
gsm.sim.operator.alpha=BodyNet LTE-M
```

Applied via ADB `setprop` on VM boot or baked into the Android-x86 system image.

### 5. Anti-Detection

- Hide emulator indicators: `ro.hardware`, `ro.kernel.qemu`, `init.svc.qemud` suppressed
- Fake sensor data: accelerometer, gyroscope, magnetometer return plausible values (not all-zeros)
- Battery status: report 73% discharging (not "AC powered" which flags emulators)
- No root/su visible to apps (Magisk Hide or equivalent if rooted)
- Screen resolution set to a common mobile resolution (1080x2400) not desktop

### 6. Helper Scripts

**`android-emu-start`:**
- Creates qcow2 disk if missing (40 GB, thin-provisioned)
- Boots VM from ISO (first run) or disk (subsequent)
- Applies `build.prop` stent identity via ADB after boot
- Waits for VM boot, then starts NMEA feed if a profile was previously set

**`android-emu-gps`:**
- Location profile management (set/list/clear)
- NMEA sentence generation (GGA, RMC, GSV with realistic satellite geometry)
- GPX route replay with configurable speed
- Proton VPN server rotation to match spoofed region
- Timezone/locale/DNS push via ADB

Both scripts installed to PATH via the module (same pattern as `game-install`).

## Files Changed

| File | Change |
|---|---|
| `modules/android-emulator.nix` | New module (all VM, network, GPS, scripts) |
| `lib/default.nix` | Add import for `android-emulator.nix` |

## Location Profiles (Initial Set)

| Profile | Coords | VPN Region | Timezone | Locale |
|---|---|---|---|---|
| `tokyo` | 35.6762, 139.6503 | JP | Asia/Tokyo | ja_JP |
| `london` | 51.5074, -0.1278 | UK | Europe/London | en_GB |
| `sydney` | -33.8688, 151.2093 | AU | Australia/Sydney | en_AU |
| `nyc` | 40.7128, -74.0060 | US-NY | America/New_York | en_US |
| `berlin` | 52.5200, 13.4050 | DE | Europe/Berlin | de_DE |
| `seoul` | 37.5665, 126.9780 | KR | Asia/Seoul | ko_KR |
| `saopaulo` | -23.5505, -46.6333 | BR | America/Sao_Paulo | pt_BR |

Users can add custom profiles via a simple config file.

## Security & Anonymity Summary

- VM is a black box: no file/clipboard/USB bridge to host
- Network kill switch: VPN down = VM offline
- Separate VPN exit from host (no traffic correlation)
- GPS + IP + timezone + locale + DNS all consistent per profile
- Device identity: cardiac stent (not detectable as emulator)
- No Google Play Services (no Google telemetry)
- Advertising ID randomized per profile switch
- Emulator indicators suppressed in build.prop and system properties
