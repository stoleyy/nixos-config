#!/usr/bin/env bash
# Quick hardware detection for fan control chip
set -euo pipefail

echo "=== Board info ==="
cat /sys/class/dmi/id/board_name 2>/dev/null || echo "unknown"
cat /sys/class/dmi/id/board_vendor 2>/dev/null || echo "unknown"
cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "unknown"

echo
echo "=== dmesg: fan/wmi/hwmon/acer ==="
dmesg 2>/dev/null | grep -iE 'acer|wmi|fan|hwmon|super.io|sio' | tail -30 || echo "(no matches or no permission)"

echo
echo "=== Loaded modules with wmi/acer/hwmon ==="
lsmod | grep -iE 'acer|wmi|hwmon|it87|nct|fan' || echo "(none)"

echo
echo "=== ISA port probe for Super I/O chip ID ==="
# Super I/O chips live at ISA ports 0x2E/0x2F or 0x4E/0x4F
# Enter config mode by writing 0x87 twice, read chip ID at reg 0x20/0x21
if command -v ioport &>/dev/null || [ -c /dev/port ]; then
  for base in 0x2e 0x4e; do
    echo "Probing Super I/O at $base..."
    # Try reading chip ID register 0x20
    python3 -c "
import struct, os
fd = os.open('/dev/port', os.O_RDWR)
base = $base
# Enter config mode (0x87 twice for most chips)
os.lseek(fd, base, 0); os.write(fd, b'\\x87')
os.lseek(fd, base, 0); os.write(fd, b'\\x87')
# Read chip ID high byte (reg 0x20)
os.lseek(fd, base, 0); os.write(fd, b'\\x20')
os.lseek(fd, base+1, 0); hi = struct.unpack('B', os.read(fd, 1))[0]
# Read chip ID low byte (reg 0x21)
os.lseek(fd, base, 0); os.write(fd, b'\\x21')
os.lseek(fd, base+1, 0); lo = struct.unpack('B', os.read(fd, 1))[0]
# Exit config mode
os.lseek(fd, base, 0); os.write(fd, b'\\xaa')
os.close(fd)
chip_id = (hi << 8) | lo
print(f'  Chip ID at {hex(base)}: 0x{chip_id:04X} (hi=0x{hi:02X} lo=0x{lo:02X})')
if hi == 0xB4: print('  -> Nuvoton NCT6775 family!')
elif hi == 0xC3: print('  -> Nuvoton NCT6776 family!')
elif hi == 0xC5: print('  -> Nuvoton NCT6779 family!')
elif hi == 0xD4: print('  -> Nuvoton NCT6797/NCT6798 family!')
elif hi == 0xD3: print('  -> Nuvoton NCT6795 family!')
elif hi == 0x87: print('  -> ITE IT87xx family!')
elif hi == 0xFF: print('  -> No chip detected (0xFFFF)')
else: print(f'  -> Unknown chip ID')
" 2>&1 || echo "  (port access failed — need root or /dev/port missing)"
  done
else
  echo "(no /dev/port — skipping ISA probe)"
fi

echo
echo "=== Trying to load common fan drivers ==="
for mod in nct6775 it87 w83627ehf f71882fg nct6683; do
  result=$(modprobe "$mod" 2>&1) && echo "$mod: LOADED" || echo "$mod: $result"
done

echo
echo "=== hwmon devices after driver load ==="
for d in /sys/class/hwmon/hwmon*/; do
  name=$(cat "${d}name" 2>/dev/null || echo "?")
  fans=0; for f in "${d}"fan*; do [ -e "$f" ] && fans=$((fans+1)); done
  pwms=0; for f in "${d}"pwm*; do [ -e "$f" ] && pwms=$((pwms+1)); done
  echo "$d -> $name (fans:$fans pwm:$pwms)"
done
