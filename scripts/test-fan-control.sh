#!/usr/bin/env bash
# Test reading and setting fan speed via ACPI _FSL/_FST methods
# TFN1 = Fan 1 (CPU fan, reads CFSP for speed)
# TFN2 = Fan 2 (reads DFSP for speed)
# TFN3 = Fan 3
set -euo pipefail

if [ ! -f /proc/acpi/call ]; then
  modprobe acpi_call 2>/dev/null || modprobe -d /run/current-system/kernel-modules acpi_call
fi

acpi_call() {
  echo "$1" > /proc/acpi/call 2>/dev/null
  cat /proc/acpi/call 2>/dev/null | tr -d '\0'
}

echo "=== Current fan status ==="
echo -n "TFN1._FST (Fan 1): "
acpi_call "\_SB.PC00.LPCB.H_EC.TFN1._FST"

echo -n "TFN2._FST (Fan 2): "
acpi_call "\_SB.PC00.LPCB.H_EC.TFN2._FST"

echo -n "TFN3._FST (Fan 3): "
acpi_call "\_SB.PC00.LPCB.H_EC.TFN3._FST"

echo
echo -n "CFAN (fan control): "
acpi_call "\_SB.PC00.LPCB.H_EC.CFAN"

echo -n "CFSP (fan1 speed): "
acpi_call "\_SB.PC00.LPCB.H_EC.CFSP"

echo -n "DFSP (fan2 speed): "
acpi_call "\_SB.PC00.LPCB.H_EC.DFSP"

echo
echo "=== Fan Performance States ==="
echo -n "TFN1._FPS: "
acpi_call "\_SB.PC00.LPCB.H_EC.TFN1._FPS"

echo
echo "=== Test: Set fan 1 to 50% (0x32) ==="
echo "Calling TFN1._FSL with 0x32 (50%)..."
echo -n "Result: "
acpi_call "\_SB.PC00.LPCB.H_EC.TFN1._FSL 0x32"

sleep 2
echo
echo "=== Re-read after setting 50% ==="
echo -n "TFN1._FST: "
acpi_call "\_SB.PC00.LPCB.H_EC.TFN1._FST"
echo -n "CFSP: "
acpi_call "\_SB.PC00.LPCB.H_EC.CFSP"
echo -n "CFAN: "
acpi_call "\_SB.PC00.LPCB.H_EC.CFAN"

echo
echo "=== Restoring fan to auto (0x64 = 100%) ==="
acpi_call "\_SB.PC00.LPCB.H_EC.TFN1._FSL 0x64"
echo "Done. Fan restored to 100% (auto control)."
