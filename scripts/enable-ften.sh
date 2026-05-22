#!/usr/bin/env bash
# Enable FTEN (Feature Enable) and re-probe WMI for fan control
set -euo pipefail

if [ ! -f /proc/acpi/call ]; then
  modprobe acpi_call 2>/dev/null || modprobe -d /run/current-system/kernel-modules acpi_call
fi

acpi_call() {
  echo "$1" > /proc/acpi/call 2>/dev/null
  cat /proc/acpi/call 2>/dev/null | tr -d '\0'
}

echo "=== Current FTEN ==="
echo -n "FTEN: "
acpi_call "\_SB.WMID.FTEN"

echo
echo "=== Writing FTEN = 1 via /dev/mem (iomem=relaxed needed) ==="

# Try devmem2 or python with /dev/mem
# If strict devmem blocks it, try via chipsec
if python3 -c "
import mmap, os
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
mm = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x775C4000)
mm[0x18] = 1
print('Written via /dev/mem')
mm.close()
os.close(fd)
" 2>/dev/null; then
  echo "Success via /dev/mem"
elif command -v chipsec_util &>/dev/null; then
  echo "Trying chipsec..."
  chipsec_util mem write 0x775C4018 0x1 1 2>&1 || echo "chipsec failed"
else
  echo "/dev/mem blocked and chipsec not found."
  echo "Trying alternative: write via ACPI OperationRegion..."
  # Create a temporary ACPI method call that writes to the SystemMemory region
  # We can write via the EC0 WIBF/IO66 mechanism or a custom approach

  # Actually, try adding iomem=relaxed to kernel params
  echo "Add 'iomem=relaxed' to boot.kernelParams and reboot, then retry."
  echo "Or use: python3 -c \"import ctypes; ...\" with appropriate permissions."
  exit 1
fi

echo
echo "=== Verify FTEN ==="
echo -n "FTEN: "
acpi_call "\_SB.WMID.FTEN"

echo
echo "=== Re-probe WMAA with FTEN=1 ==="
for input in 0x0 0x00010101 0x00010001; do
  echo -n "WMAA(0, 1, $input): "
  acpi_call "\_SB.WMID.WMAA 0x0 0x1 $input"
done

echo
echo "=== Re-probe WMBH with FTEN=1 ==="
for func in 1 2 3 4 5 6 7 8 9; do
  echo -n "WMBH(0, $func, 0): "
  acpi_call "\_SB.WMID.WMBH 0x0 0x${func} 0x0"
done

echo
echo "FTEN is volatile — reboot resets it to 0."
