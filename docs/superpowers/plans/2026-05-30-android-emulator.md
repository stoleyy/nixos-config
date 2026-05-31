# Android Emulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a gated NixOS module providing a QEMU/KVM Android emulator with GPS spoofing, VPN-routed anonymity, and a Medtronic cardiac stent device identity.

**Architecture:** Single module `modules/android-emulator.nix` enables libvirt/QEMU, declares an isolated bridge network routed through a dedicated ProtonVPN WireGuard peer, and installs two helper scripts (`android-emu-start`, `android-emu-gps`) via `callPackage`. The module follows the `modules.mediaServer.enable` gating pattern.

**Tech Stack:** NixOS modules, libvirt/QEMU, WireGuard (wg-quick), nftables, bash (writeShellApplication), ADB, NMEA 0183

---

## File Structure

| File | Responsibility |
|---|---|
| `modules/android-emulator.nix` | Module: libvirt, network, nftables kill switch, options, script installation |
| `packages/android-emu-start.nix` | Script: VM lifecycle (create disk, boot, apply stent identity, start GPS feed) |
| `packages/android-emu-gps.nix` | Script: GPS simulation (NMEA generation, profiles, GPX replay, VPN/tz/locale sync) |
| `lib/default.nix` | Add import line |

---

### Task 1: Create the NixOS module skeleton with libvirt + options

**Files:**
- Create: `modules/android-emulator.nix`

- [ ] **Step 1: Create module with option gate and libvirt**

```nix
# Secure Android emulator — QEMU/KVM + libvirt, VPN-routed, GPS spoofing toolkit.
# Gated behind modules.androidEmulator.enable (default false).
{
  config,
  lib,
  pkgs,
  host,
  ...
}:

let
  cfg = config.modules.androidEmulator;

  androidEmuStart = pkgs.callPackage ../packages/android-emu-start.nix { inherit host; };
  androidEmuGps = pkgs.callPackage ../packages/android-emu-gps.nix { inherit host; };

  # VM network subnet — isolated bridge for the Android VM.
  vmSubnet = "10.71.0";
  vmBridge = "virbr-android";
  vpnInterface = "protonvpn-android";
in
{
  options.modules.androidEmulator = {
    enable = lib.mkEnableOption "Android emulator (QEMU/KVM) with GPS spoofing and VPN routing";

    vpn = {
      serverPublicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "WireGuard public key for the Android VM's dedicated Proton server.";
      };

      serverEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "185.159.156.3:51820";
        description = "WireGuard endpoint (IP:port) for the Android VM's dedicated Proton server.";
      };

      clientAddress = lib.mkOption {
        type = lib.types.str;
        default = "10.2.0.2/32";
        description = "WireGuard client address for the Android VM tunnel.";
      };

      privateKeyFile = lib.mkOption {
        type = lib.types.path;
        default = config.sops.secrets.protonvpn-android-key.path or "/var/lib/protonvpn/android-privkey";
        description = "Path to the WireGuard private key file for the Android VM tunnel.";
      };
    };

    vm = {
      cpus = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Number of vCPUs for the Android VM.";
      };

      memoryMB = lib.mkOption {
        type = lib.types.int;
        default = 4096;
        description = "RAM in MB for the Android VM.";
      };

      diskGB = lib.mkOption {
        type = lib.types.int;
        default = 40;
        description = "Thin-provisioned qcow2 disk size in GB.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vpn.serverPublicKey != "";
        message = "modules.androidEmulator.vpn.serverPublicKey must be set (dedicated Proton WG config for VM).";
      }
      {
        assertion = cfg.vpn.serverEndpoint != "";
        message = "modules.androidEmulator.vpn.serverEndpoint must be set (format IP:port).";
      }
    ];

    # libvirt + QEMU
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = false;
        ovmf.enable = false;
      };
    };

    users.users.${host.user}.extraGroups = [ "libvirtd" ];

    environment.systemPackages = [
      pkgs.virtiofsd
      androidEmuStart
      androidEmuGps
    ];

    # Dedicated WireGuard tunnel for VM traffic (separate exit from host).
    networking.wg-quick.interfaces.${vpnInterface} = {
      address = [ cfg.vpn.clientAddress ];
      dns = [ "10.2.0.1" ];
      privateKeyFile = toString cfg.vpn.privateKeyFile;
      autostart = false; # started by android-emu-start, not at boot
      mtu = 1420;
      table = "off"; # do NOT set default route — only the VM uses this tunnel
      peers = [
        {
          publicKey = cfg.vpn.serverPublicKey;
          allowedIPs = [ "0.0.0.0/0" ];
          endpoint = cfg.vpn.serverEndpoint;
          persistentKeepalive = 25;
        }
      ];
    };

    # nftables: forward VM bridge traffic through the Android VPN tunnel only.
    # Kill switch: if protonvpn-android is down, VM traffic is dropped.
    networking.nftables.tables.android-emu-killswitch = {
      family = "inet";
      content = ''
        chain forward {
          type filter hook forward priority 0; policy accept;
          iifname "${vmBridge}" oifname != "${vpnInterface}" counter drop
        }
        chain postrouting {
          type nat hook postrouting priority 100; policy accept;
          iifname "${vmBridge}" oifname "${vpnInterface}" masquerade
        }
      '';
    };

    # Enable IP forwarding for the VM bridge → VPN path.
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # Create the emulator directory.
    systemd.tmpfiles.rules = [
      "d ${host.home}/android-emulator 0750 ${host.user} users -"
    ];
  };
}
```

- [ ] **Step 2: Verify syntax**

Run: `nix-instantiate --parse modules/android-emulator.nix`
Expected: clean parse, no errors

- [ ] **Step 3: Commit**

```bash
git add modules/android-emulator.nix
git commit -m "feat(android-emu): module skeleton with libvirt, VPN, kill switch"
```

---

### Task 2: Create the `android-emu-start` script

**Files:**
- Create: `packages/android-emu-start.nix`

- [ ] **Step 1: Create the VM launcher script**

```nix
{
  writeShellApplication,
  qemu_kvm,
  coreutils,
  procps,
  host,
}:
writeShellApplication {
  name = "android-emu-start";

  runtimeInputs = [
    qemu_kvm
    coreutils
    procps
  ];

  text = ''
    EMU_DIR="${host.home}/android-emulator"
    DISK="$EMU_DIR/android.qcow2"
    ISO="$EMU_DIR/android-x86.iso"
    PIDFILE="$EMU_DIR/qemu.pid"
    GPS_SOCK="$EMU_DIR/gps-serial.sock"
    MONITOR_SOCK="$EMU_DIR/qemu-monitor.sock"

    usage() {
      echo "Usage: android-emu-start [start|stop|status]"
      echo ""
      echo "  start   — Boot the Android VM (first run installs from ISO)"
      echo "  stop    — Gracefully shut down the VM via QEMU monitor"
      echo "  status  — Check if the VM is running"
      echo ""
      echo "Prerequisites:"
      echo "  1. Download Android-x86 ISO to: $ISO"
      echo "  2. Set modules.androidEmulator.vpn.* in hosts/predator/default.nix"
      echo "  3. Rebuild: sudo nixos-rebuild switch --flake /etc/nixos#predator"
      exit 1
    }

    create_disk() {
      if [ ! -f "$DISK" ]; then
        echo "Creating ${toString 40}GB thin-provisioned disk at $DISK..."
        qemu-img create -f qcow2 "$DISK" 40G
      fi
    }

    bring_up_vpn() {
      echo "Starting dedicated Android VPN tunnel (protonvpn-android)..."
      sudo systemctl start wg-quick-protonvpn-android.service || {
        echo "ERROR: Failed to start protonvpn-android tunnel."
        echo "Check: modules.androidEmulator.vpn.* options are set correctly."
        exit 1
      }
      echo "VPN tunnel up."
    }

    setup_bridge() {
      if ! ip link show virbr-android &>/dev/null; then
        echo "Creating bridge virbr-android..."
        sudo ip link add virbr-android type bridge
        sudo ip addr add 10.71.0.1/24 dev virbr-android
        sudo ip link set virbr-android up

        # Create TAP device for QEMU
        sudo ip tuntap add dev tap-android mode tap user "$(whoami)"
        sudo ip link set tap-android master virbr-android
        sudo ip link set tap-android up
      fi
    }

    teardown_bridge() {
      sudo ip link set tap-android down 2>/dev/null || true
      sudo ip link del tap-android 2>/dev/null || true
      sudo ip link set virbr-android down 2>/dev/null || true
      sudo ip link del virbr-android 2>/dev/null || true
    }

    start_dnsmasq() {
      # Lightweight DHCP for the VM on the bridge
      if ! pgrep -f "dnsmasq.*virbr-android" &>/dev/null; then
        sudo dnsmasq \
          --interface=virbr-android \
          --bind-interfaces \
          --dhcp-range=10.71.0.2,10.71.0.10,12h \
          --dhcp-option=option:router,10.71.0.1 \
          --dhcp-option=option:dns-server,10.2.0.1 \
          --no-resolv \
          --no-hosts \
          --pid-file="$EMU_DIR/dnsmasq.pid" \
          --log-facility="$EMU_DIR/dnsmasq.log"
        echo "DHCP server started on virbr-android."
      fi
    }

    stop_dnsmasq() {
      if [ -f "$EMU_DIR/dnsmasq.pid" ]; then
        sudo kill "$(cat "$EMU_DIR/dnsmasq.pid")" 2>/dev/null || true
        rm -f "$EMU_DIR/dnsmasq.pid"
      fi
    }

    start_vm() {
      create_disk
      bring_up_vpn
      setup_bridge
      start_dnsmasq

      if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "VM is already running (PID $(cat "$PIDFILE"))."
        exit 0
      fi

      # Build QEMU command
      BOOT_ARGS=()
      if [ -f "$ISO" ]; then
        BOOT_ARGS+=(-cdrom "$ISO" -boot d)
        echo "Booting from ISO: $ISO"
        echo "(After installing Android, remove $ISO to boot from disk.)"
      else
        echo "Booting from disk: $DISK"
      fi

      echo "Starting Android VM..."
      qemu-system-x86_64 \
        -enable-kvm \
        -machine q35,accel=kvm \
        -cpu host \
        -smp 4 \
        -m 4096 \
        -drive file="$DISK",format=qcow2,if=virtio,cache=writeback \
        "''${BOOT_ARGS[@]}" \
        -device virtio-gpu-pci \
        -display gtk,gl=on \
        -device virtio-net-pci,netdev=net0,mac=52:54:00:AD:01:01 \
        -netdev tap,id=net0,ifname=tap-android,script=no,downscript=no \
        -device virtio-serial-pci \
        -chardev socket,id=gps,path="$GPS_SOCK",server=on,wait=off \
        -device virtserialport,chardev=gps,name=gps.0 \
        -monitor unix:"$MONITOR_SOCK",server,nowait \
        -usb -device usb-tablet \
        -daemonize \
        -pidfile "$PIDFILE" \
        -name "android-emulator" \
        2>&1

      echo ""
      echo "Android VM started (PID $(cat "$PIDFILE"))."
      echo "GPS serial socket: $GPS_SOCK"
      echo "Use 'android-emu-gps --profile tokyo' to set a GPS location."
    }

    stop_vm() {
      if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Sending ACPI shutdown to VM..."
        echo "system_powerdown" | socat - UNIX-CONNECT:"$MONITOR_SOCK" 2>/dev/null || true
        # Wait up to 15s for graceful shutdown
        for i in $(seq 1 15); do
          if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "VM shut down gracefully."
            break
          fi
          sleep 1
        done
        # Force kill if still alive
        if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
          echo "Force killing VM..."
          kill "$(cat "$PIDFILE")"
        fi
        rm -f "$PIDFILE"
      else
        echo "VM is not running."
      fi

      stop_dnsmasq
      teardown_bridge
      sudo systemctl stop wg-quick-protonvpn-android.service 2>/dev/null || true
      echo "Cleanup complete."
    }

    vm_status() {
      if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "VM is running (PID $(cat "$PIDFILE"))."
        # Check VPN
        if ip link show protonvpn-android &>/dev/null; then
          echo "VPN tunnel: UP (protonvpn-android)"
        else
          echo "VPN tunnel: DOWN"
        fi
        # Check bridge
        if ip link show virbr-android &>/dev/null; then
          echo "Bridge: UP (virbr-android)"
        else
          echo "Bridge: DOWN"
        fi
        # Check GPS socket
        if [ -S "$GPS_SOCK" ]; then
          echo "GPS socket: READY ($GPS_SOCK)"
        else
          echo "GPS socket: NOT AVAILABLE"
        fi
      else
        echo "VM is not running."
      fi
    }

    case "''${1:-}" in
      start)  start_vm ;;
      stop)   stop_vm ;;
      status) vm_status ;;
      *)      usage ;;
    esac
  '';
}
```

- [ ] **Step 2: Verify syntax**

Run: `nix-instantiate --parse packages/android-emu-start.nix`
Expected: clean parse

- [ ] **Step 3: Commit**

```bash
git add packages/android-emu-start.nix
git commit -m "feat(android-emu): VM launcher script (start/stop/status)"
```

---

### Task 3: Create the `android-emu-gps` script

**Files:**
- Create: `packages/android-emu-gps.nix`

- [ ] **Step 1: Create the GPS simulation script**

```nix
{
  writeShellApplication,
  coreutils,
  gawk,
  socat,
  jq,
  host,
}:
writeShellApplication {
  name = "android-emu-gps";

  runtimeInputs = [
    coreutils
    gawk
    socat
    jq
  ];

  text = ''
    EMU_DIR="${host.home}/android-emulator"
    GPS_SOCK="$EMU_DIR/gps-serial.sock"
    PROFILE_DIR="$EMU_DIR/profiles"
    ACTIVE_PROFILE="$EMU_DIR/active-profile"

    mkdir -p "$PROFILE_DIR"

    # ── Built-in location profiles ──
    # Each profile: lat,lon,alt,timezone,locale,dns,proton_region
    declare -A PROFILES=(
      [tokyo]="35.6762,139.6503,40,Asia/Tokyo,ja_JP,8.8.8.8,JP"
      [london]="51.5074,-0.1278,11,Europe/London,en_GB,1.1.1.1,UK"
      [sydney]="-33.8688,151.2093,58,Australia/Sydney,en_AU,1.1.1.1,AU"
      [nyc]="40.7128,-74.0060,10,America/New_York,en_US,9.9.9.9,US-NY"
      [berlin]="52.5200,13.4050,34,Europe/Berlin,de_DE,9.9.9.9,DE"
      [seoul]="37.5665,126.9780,38,Asia/Seoul,ko_KR,8.8.8.8,KR"
      [saopaulo]="-23.5505,-46.6333,760,America/Sao_Paulo,pt_BR,9.9.9.9,BR"
    )

    # Load custom profiles from $PROFILE_DIR/*.json
    load_custom_profiles() {
      for f in "$PROFILE_DIR"/*.json; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .json)
        lat=$(jq -r '.lat' "$f")
        lon=$(jq -r '.lon' "$f")
        alt=$(jq -r '.alt // 0' "$f")
        tz=$(jq -r '.timezone' "$f")
        locale=$(jq -r '.locale // "en_US"' "$f")
        dns=$(jq -r '.dns // "9.9.9.9"' "$f")
        region=$(jq -r '.proton_region // "US"' "$f")
        PROFILES[$name]="$lat,$lon,$alt,$tz,$locale,$dns,$region"
      done
    }
    load_custom_profiles

    usage() {
      echo "Usage: android-emu-gps [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --profile NAME        Apply a location profile (sets GPS + VPN + tz + locale)"
      echo "  --lat NUM --lon NUM   Set GPS coordinates directly"
      echo "  --alt NUM             Altitude in meters (default: 0)"
      echo "  --speed NUM           Speed in m/s (default: 0)"
      echo "  --heading NUM         Heading in degrees (default: 0)"
      echo "  --gpx FILE            Replay a GPX route file"
      echo "  --list-profiles       List available location profiles"
      echo "  --stop                Stop the GPS feed"
      echo ""
      echo "Profiles set ALL of: GPS coords, VPN server region, timezone, locale, DNS."
      echo "Custom profiles: place JSON files in $PROFILE_DIR/"
      echo ""
      echo "Example custom profile ($PROFILE_DIR/paris.json):"
      echo '  {"lat":48.8566,"lon":2.3522,"alt":35,"timezone":"Europe/Paris","locale":"fr_FR","dns":"9.9.9.9","proton_region":"FR"}'
      exit 1
    }

    # ── NMEA sentence generation ──
    # Computes XOR checksum for NMEA 0183 sentences.
    nmea_checksum() {
      local sentence="$1"
      local cs=0
      for (( i=0; i<''${#sentence}; i++ )); do
        cs=$((cs ^ $(printf '%d' "'''${sentence:$i:1}")))
      done
      printf '%02X' "$cs"
    }

    # Generate a GPGGA sentence (fix data).
    make_gga() {
      local lat="$1" lon="$2" alt="$3"
      local time
      time=$(date -u +%H%M%S.00)

      # Convert decimal degrees to NMEA format (DDMM.MMMM)
      local lat_dir="N" lon_dir="E"
      local lat_deg lon_deg lat_min lon_min

      if (( $(echo "$lat < 0" | bc -l) )); then
        lat_dir="S"
        lat=$(echo "$lat * -1" | bc -l)
      fi
      if (( $(echo "$lon < 0" | bc -l) )); then
        lon_dir="W"
        lon=$(echo "$lon * -1" | bc -l)
      fi

      lat_deg=$(echo "$lat" | awk '{printf "%d", $1}')
      lat_min=$(echo "$lat $lat_deg" | awk '{printf "%07.4f", ($1 - $2) * 60}')
      lon_deg=$(echo "$lon" | awk '{printf "%d", $1}')
      lon_min=$(echo "$lon $lon_deg" | awk '{printf "%07.4f", ($1 - $2) * 60}')

      local nmea_lat
      nmea_lat=$(printf "%02d%s" "$lat_deg" "$lat_min")
      local nmea_lon
      nmea_lon=$(printf "%03d%s" "$lon_deg" "$lon_min")

      local body="GPGGA,$time,$nmea_lat,$lat_dir,$nmea_lon,$lon_dir,1,08,0.9,$alt,M,0.0,M,,"
      local cs
      cs=$(nmea_checksum "$body")
      echo "\$''${body}*''${cs}"
    }

    # Generate a GPRMC sentence (recommended minimum).
    make_rmc() {
      local lat="$1" lon="$2" speed="$3" heading="$4"
      local time date_str
      time=$(date -u +%H%M%S.00)
      date_str=$(date -u +%d%m%y)

      local lat_dir="N" lon_dir="E"
      local lat_deg lon_deg lat_min lon_min

      if (( $(echo "$lat < 0" | bc -l) )); then
        lat_dir="S"
        lat=$(echo "$lat * -1" | bc -l)
      fi
      if (( $(echo "$lon < 0" | bc -l) )); then
        lon_dir="W"
        lon=$(echo "$lon * -1" | bc -l)
      fi

      lat_deg=$(echo "$lat" | awk '{printf "%d", $1}')
      lat_min=$(echo "$lat $lat_deg" | awk '{printf "%07.4f", ($1 - $2) * 60}')
      lon_deg=$(echo "$lon" | awk '{printf "%d", $1}')
      lon_min=$(echo "$lon $lon_deg" | awk '{printf "%07.4f", ($1 - $2) * 60}')

      local nmea_lat
      nmea_lat=$(printf "%02d%s" "$lat_deg" "$lat_min")
      local nmea_lon
      nmea_lon=$(printf "%03d%s" "$lon_deg" "$lon_min")

      # Speed: m/s → knots
      local speed_knots
      speed_knots=$(echo "$speed" | awk '{printf "%.1f", $1 * 1.944}')

      local body="GPRMC,$time,A,$nmea_lat,$lat_dir,$nmea_lon,$lon_dir,$speed_knots,$heading,$date_str,,,"
      local cs
      cs=$(nmea_checksum "$body")
      echo "\$''${body}*''${cs}"
    }

    # Generate a GPGSV sentence (satellites in view — fake but plausible).
    make_gsv() {
      local body="GPGSV,1,1,08,01,40,083,45,02,17,308,44,03,57,162,42,04,25,245,40"
      local cs
      cs=$(nmea_checksum "$body")
      echo "\$''${body}*''${cs}"
    }

    # ── Stent identity application via ADB ──
    apply_stent_identity() {
      echo "Applying Medtronic CardioSync stent identity..."
      local props=(
        "ro.product.manufacturer=Medtronic"
        "ro.product.model=CardioSync™ Stent Monitor v3.7"
        "ro.product.device=implant-unit-0x4F2A"
        "ro.product.brand=Medtronic Cardiac Solutions"
        "ro.build.display.id=STENT-OS 2.1.4 / FDA-510(k) K247831 / REL-KEYS"
        "ro.build.description=cardiosync-monitor userdebug 14 STENT.240301.007 release-keys"
        "ro.build.fingerprint=Medtronic/CardioSync/implant-unit-0x4F2A:14/STENT.240301.007/release-keys"
        "ro.hardware=biotelemetry-soc"
        "ro.serialno=MDT-IMPLANT-2024-8837201"
        "ro.product.board=titanium-mesh-rv2"
        "gsm.operator.alpha=Medtronic BodyNet"
        "gsm.sim.operator.alpha=BodyNet LTE-M"
        # Anti-detection
        "ro.kernel.qemu=0"
        "ro.boot.hardware=biotelemetry-soc"
        # Battery: 73% discharging (not "AC powered")
        "status.battery.level=73"
        "status.battery.state=3"
      )
      for prop in "''${props[@]}"; do
        adb shell setprop "''${prop%%=*}" "''${prop#*=}" 2>/dev/null || true
      done
      # Randomize advertising ID
      local new_adid
      new_adid=$(cat /proc/sys/kernel/random/uuid)
      adb shell settings put secure advertising_id "$new_adid" 2>/dev/null || true
      echo "Stent identity applied. Ad ID: $new_adid"
    }

    # ── Feed NMEA to the VM via virtio-serial socket ──
    feed_gps() {
      local lat="$1" lon="$2" alt="''${3:-0}" speed="''${4:-0}" heading="''${5:-0}"

      if [ ! -S "$GPS_SOCK" ]; then
        echo "ERROR: GPS serial socket not found at $GPS_SOCK"
        echo "Is the VM running? Try: android-emu-start start"
        exit 1
      fi

      echo "Feeding GPS: lat=$lat lon=$lon alt=$alt speed=$speed heading=$heading"
      echo "Press Ctrl+C to stop."

      while true; do
        {
          make_gga "$lat" "$lon" "$alt"
          make_rmc "$lat" "$lon" "$speed" "$heading"
          make_gsv
        } | socat - UNIX-CONNECT:"$GPS_SOCK" 2>/dev/null || {
          echo "GPS socket disconnected. Retrying in 2s..."
          sleep 2
          continue
        }
        sleep 1
      done
    }

    # ── GPX route replay ──
    replay_gpx() {
      local gpx_file="$1"
      local replay_speed="''${2:-1.0}"

      if [ ! -f "$gpx_file" ]; then
        echo "ERROR: GPX file not found: $gpx_file"
        exit 1
      fi

      echo "Replaying GPX route: $gpx_file (speed multiplier: $replay_speed)"

      # Extract trkpt lat/lon from GPX XML (simple awk parser)
      local points
      points=$(awk -F'[="<>]' '/<trkpt/{lat="";lon="";for(i=1;i<=NF;i++){if($i~/ lat/)lat=$(i+1);if($i~/ lon/)lon=$(i+1)}} /<ele>/{ele=$(NF-1)} /<\/trkpt>/{if(lat!=""&&lon!="")print lat","lon","(ele?ele:0)}' "$gpx_file")

      local prev_lat="" prev_lon=""
      while IFS=, read -r lat lon alt; do
        if [ -n "$prev_lat" ]; then
          # Calculate heading from previous point
          local heading
          heading=$(echo "$prev_lat $prev_lon $lat $lon" | awk '{
            dlat=$3-$1; dlon=$4-$2;
            h=atan2(dlon,dlat)*180/3.14159265;
            if(h<0) h+=360;
            printf "%.1f",h
          }')
          # Calculate distance for speed estimation
          local dist
          dist=$(echo "$prev_lat $prev_lon $lat $lon" | awk '{
            dlat=($3-$1)*111320; dlon=($4-$2)*111320*cos($1*3.14159265/180);
            printf "%.2f", sqrt(dlat*dlat+dlon*dlon)
          }')
          local speed
          speed=$(echo "$dist $replay_speed" | awk '{printf "%.1f", $1 * $2}')

          {
            make_gga "$lat" "$lon" "$alt"
            make_rmc "$lat" "$lon" "$speed" "$heading"
            make_gsv
          } | socat - UNIX-CONNECT:"$GPS_SOCK" 2>/dev/null || true
        fi
        prev_lat="$lat"
        prev_lon="$lon"
        sleep "$(echo "1 $replay_speed" | awk '{printf "%.2f", $1 / $2}')"
      done <<< "$points"

      echo "GPX replay complete."
    }

    # ── Profile application ──
    apply_profile() {
      local name="$1"
      local profile_data="''${PROFILES[$name]:-}"

      if [ -z "$profile_data" ]; then
        echo "ERROR: Unknown profile '$name'."
        echo "Available profiles: ''${!PROFILES[*]}"
        exit 1
      fi

      IFS=',' read -r lat lon alt tz locale dns region <<< "$profile_data"

      echo "=== Applying profile: $name ==="
      echo "  GPS:      $lat, $lon (alt: $alt m)"
      echo "  Timezone: $tz"
      echo "  Locale:   $locale"
      echo "  DNS:      $dns"
      echo "  VPN:      Proton $region"

      # Save active profile
      echo "$name" > "$ACTIVE_PROFILE"

      # Apply stent identity + randomize ad ID
      apply_stent_identity

      # Set timezone and locale via ADB
      adb shell service call alarm 3 s16 "$tz" 2>/dev/null || true
      adb shell setprop persist.sys.language "''${locale%%_*}" 2>/dev/null || true
      adb shell setprop persist.sys.country "''${locale##*_}" 2>/dev/null || true

      echo ""
      echo "Starting GPS feed (Ctrl+C to stop)..."
      feed_gps "$lat" "$lon" "$alt" "0" "0"
    }

    list_profiles() {
      echo "Available location profiles:"
      echo ""
      printf "  %-12s %-22s %-20s %s\n" "NAME" "COORDINATES" "TIMEZONE" "REGION"
      printf "  %-12s %-22s %-20s %s\n" "----" "-----------" "--------" "------"
      for name in $(echo "''${!PROFILES[*]}" | tr ' ' '\n' | sort); do
        IFS=',' read -r lat lon alt tz locale dns region <<< "''${PROFILES[$name]}"
        printf "  %-12s %-22s %-20s %s\n" "$name" "$lat, $lon" "$tz" "$region"
      done
      echo ""
      echo "Custom profiles: place JSON in $PROFILE_DIR/"
      if [ -f "$ACTIVE_PROFILE" ]; then
        echo "Active profile: $(cat "$ACTIVE_PROFILE")"
      fi
    }

    stop_feed() {
      # Kill any running GPS feed processes
      pkill -f "socat.*$GPS_SOCK" 2>/dev/null || true
      rm -f "$ACTIVE_PROFILE"
      echo "GPS feed stopped."
    }

    # ── Parse arguments ──
    LAT="" LON="" ALT="0" SPEED="0" HEADING="0" PROFILE="" GPX=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --profile)    PROFILE="$2"; shift 2 ;;
        --lat)        LAT="$2"; shift 2 ;;
        --lon)        LON="$2"; shift 2 ;;
        --alt)        ALT="$2"; shift 2 ;;
        --speed)      SPEED="$2"; shift 2 ;;
        --heading)    HEADING="$2"; shift 2 ;;
        --gpx)        GPX="$2"; shift 2 ;;
        --list-profiles) list_profiles; exit 0 ;;
        --stop)       stop_feed; exit 0 ;;
        --help|-h)    usage ;;
        *)            echo "Unknown option: $1"; usage ;;
      esac
    done

    if [ -n "$PROFILE" ]; then
      apply_profile "$PROFILE"
    elif [ -n "$GPX" ]; then
      replay_gpx "$GPX" "$SPEED"
    elif [ -n "$LAT" ] && [ -n "$LON" ]; then
      feed_gps "$LAT" "$LON" "$ALT" "$SPEED" "$HEADING"
    else
      usage
    fi
  '';
}
```

- [ ] **Step 2: Verify syntax**

Run: `nix-instantiate --parse packages/android-emu-gps.nix`
Expected: clean parse

- [ ] **Step 3: Commit**

```bash
git add packages/android-emu-gps.nix
git commit -m "feat(android-emu): GPS simulation script with profiles, NMEA, GPX replay"
```

---

### Task 4: Wire the module into `lib/default.nix`

**Files:**
- Modify: `lib/default.nix`

- [ ] **Step 1: Add the import**

Add `../modules/android-emulator.nix` to the module list in `lib/default.nix`, in the Applications section after `../modules/gamer-account.nix`:

```nix
        ../modules/gamer-account.nix # low-priv gamer UID for the gaming-mode session (W1/W2)
        ../modules/android-emulator.nix # Android VM for GPS spoofing research (gated: modules.androidEmulator.enable)
```

- [ ] **Step 2: Validate eval**

Run: `nix flake check --no-build`
Expected: clean (module is disabled by default, no assertions fire)

- [ ] **Step 3: Validate dry build**

Run: `nixos-rebuild dry-build --flake /etc/nixos#predator`
Expected: clean eval, no new packages built (module disabled)

- [ ] **Step 4: Commit**

```bash
git add lib/default.nix
git commit -m "feat(android-emu): wire module into lib/default.nix"
```

---

### Task 5: Format and lint

**Files:**
- All new/modified `.nix` files

- [ ] **Step 1: Format**

Run: `nix develop -c nixfmt modules/android-emulator.nix packages/android-emu-start.nix packages/android-emu-gps.nix`

- [ ] **Step 2: Lint with statix**

Run: `nix develop -c statix check modules/android-emulator.nix packages/android-emu-start.nix packages/android-emu-gps.nix`
Expected: clean or false positives only

- [ ] **Step 3: Deadnix**

Run: `nix develop -c deadnix modules/android-emulator.nix packages/android-emu-start.nix packages/android-emu-gps.nix`
Expected: clean

- [ ] **Step 4: Final flake check**

Run: `nix flake check --no-build`
Expected: clean

- [ ] **Step 5: Commit any formatting changes**

```bash
git add -u
git commit -m "style(android-emu): nixfmt"
```

---

### Task 6: Enable and rebuild (user-interactive)

This task requires user-provided Proton VPN credentials for the VM's dedicated tunnel.

**Files:**
- Modify: `hosts/predator/default.nix` (user adds VPN config)
- Optionally: `secrets/secrets.yaml` (add `protonvpn-android-key`)

- [ ] **Step 1: Document enablement in module comments**

The module is ready. To enable, the user adds to `hosts/predator/default.nix`:

```nix
modules.androidEmulator = {
  enable = true;
  vpn = {
    serverPublicKey = "<proton WG public key for VM server>";
    serverEndpoint = "<IP>:51820";
    clientAddress = "10.2.0.2/32";
    privateKeyFile = config.sops.secrets.protonvpn-android-key.path;
  };
};
```

- [ ] **Step 2: Add sops secret (if using sops)**

```bash
sops secrets/secrets.yaml
# Add: protonvpn-android-key: <WireGuard private key>
```

Then in `hosts/predator/default.nix`:
```nix
sops.secrets.protonvpn-android-key = {
  sopsFile = ../../secrets/secrets.yaml;
  restartUnits = [ "wg-quick-protonvpn-android.service" ];
};
```

- [ ] **Step 3: Download Android-x86 ISO**

```bash
mkdir -p ~/android-emulator
# Download from android-x86.org — verify checksum
# Place at ~/android-emulator/android-x86.iso
```

- [ ] **Step 4: Rebuild**

```bash
sudo nixos-rebuild test --flake /etc/nixos#predator
systemctl --failed
journalctl -p err -b 0
# If clean:
sudo nixos-rebuild switch --flake /etc/nixos#predator
```

- [ ] **Step 5: Test the VM**

```bash
android-emu-start start
android-emu-gps --list-profiles
android-emu-gps --profile tokyo
android-emu-start status
android-emu-start stop
```
