#!/usr/bin/env bash
# Probe WMBH (Acer WMI) method with various function IDs to find fan control
set -euo pipefail

if [ ! -f /proc/acpi/call ]; then
  modprobe acpi_call 2>/dev/null || modprobe -d /run/current-system/kernel-modules acpi_call
fi

acpi_call() {
  echo "$1" > /proc/acpi/call 2>/dev/null
  cat /proc/acpi/call 2>/dev/null | tr -d '\0'
}

echo "=== FTEN (feature enable) ==="
echo -n "FTEN: "
acpi_call "\_SB.WMID.FTEN"

echo
echo "=== WMBH probing (Acer WMI standard interface) ==="
echo "WMBH takes (instance, func_id, input_buffer)"
echo

# Try all function IDs 1-10 with input 0
for func in 1 2 3 4 5 6 7 8; do
  echo -n "WMBH(0, $func, 0): "
  acpi_call "\_SB.WMID.WMBH 0x0 0x${func} 0x0"
done

echo
echo "=== WMAA probing with different input buffers ==="
# PredatorSense sends specific command payloads
# Common patterns: first byte = command type, second = subcommand
# Try reading fan speed (common Acer WMI cmd patterns)
for input in 0x00010101 0x00010001 0x00020001 0x00030001 0x00040001 0x00050001 0x01000001 0x02000001; do
  echo -n "WMAA(0, 1, $input): "
  acpi_call "\_SB.WMID.WMAA 0x0 0x1 $input"
done

echo
echo "=== EC0 command probing (safe read-only commands) ==="
# EC0.ECMD sends a command byte to EC port 0x66
# Try common info/read commands (0x00-0x10 are usually safe)
for cmd in 0x00 0x01 0x02 0x03 0x04 0x05 0x10 0x11 0x12 0x80; do
  echo -n "EC0.ECMD($cmd): "
  acpi_call "\_SB.PC00.LPCB.EC0.ECMD $cmd"
done

echo
echo "=== Full EC dump via dd ==="
echo "Current EC register 0x18 (temp): $(od -An -tx1 -j 24 -N 1 /sys/kernel/debug/ec/ec0/io | tr -d ' ')"
echo "Reading all 256 EC bytes for reference:"
od -An -tx1 /sys/kernel/debug/ec/ec0/io | head -16
