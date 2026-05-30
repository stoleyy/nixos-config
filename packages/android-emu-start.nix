{
  writeShellApplication,
  qemu_kvm,
  coreutils,
  procps,
  socat,
  dnsmasq,
  iproute2,
  host,
}:
writeShellApplication {
  name = "android-emu-start";

  runtimeInputs = [
    qemu_kvm
    coreutils
    procps
    socat
    dnsmasq
    iproute2
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
        echo "Creating 40GB thin-provisioned disk at $DISK..."
        qemu-img create -f qcow2 "$DISK" 40G
      fi
    }

    bring_up_vpn() {
      echo "Starting dedicated Android VPN tunnel (pvpn-android)..."
      sudo systemctl start wg-quick-pvpn-android.service || {
        echo "ERROR: Failed to start pvpn-android tunnel."
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
      if ! pgrep -f "dnsmasq.*virbr-android" &>/dev/null; then
        sudo dnsmasq \
          --user=root \
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
        for _i in $(seq 1 15); do
          if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "VM shut down gracefully."
            break
          fi
          sleep 1
        done
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
      sudo systemctl stop wg-quick-pvpn-android.service 2>/dev/null || true
      echo "Cleanup complete."
    }

    vm_status() {
      if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "VM is running (PID $(cat "$PIDFILE"))."
        if ip link show pvpn-android &>/dev/null; then
          echo "VPN tunnel: UP (pvpn-android)"
        else
          echo "VPN tunnel: DOWN"
        fi
        if ip link show virbr-android &>/dev/null; then
          echo "Bridge: UP (virbr-android)"
        else
          echo "Bridge: DOWN"
        fi
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
