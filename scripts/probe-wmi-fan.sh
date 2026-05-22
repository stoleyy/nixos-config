#!/usr/bin/env bash
# Probe WMI BMOF and ACPI methods to find Acer PredatorSense fan control.
# The BMOF (Binary MOF) describes what WMI methods the firmware exposes.
# PredatorSense on Windows calls these methods for fan speed control.
set -euo pipefail

echo "=== WMI BMOF data ==="
# The wmi-bmof driver exposes MOF data at /sys/bus/wmi/devices/<GUID>/bmof
for bmof in /sys/bus/wmi/devices/*/bmof; do
  [ -f "$bmof" ] || continue
  guid=$(basename "$(dirname "$bmof")")
  echo "--- BMOF for $guid ---"
  # Dump raw BMOF and try to find readable strings (method names, class names)
  strings "$bmof" 2>/dev/null | head -50
  echo
done

echo "=== ACPI namespace: fan/thermal methods ==="
# Check if acpi_call module is available
if modprobe acpi_call 2>/dev/null; then
  echo "acpi_call module loaded"

  # Try known Acer WMI ACPI paths for fan control
  # PredatorSense typically uses \_SB.WMID or \_SB.WMI1 methods
  for path in \
    '\_SB.WMID.WMAA' \
    '\_SB.WMI1.WMAA' \
    '\_SB.WMID.WMBA' \
    '\_SB.WMI2.WMBA' \
    '\_SB.ATKD.WMNB' \
    '\_SB.PCI0.LPCB.EC0._Q11' \
    '\_SB.PCI0.LPCB.EC0.SFNV' \
    '\_SB.PCI0.LPCB.EC0.GFNS' \
    '\_TZ.FAN0._FST' \
    '\_TZ.TZ00._AC0' \
    '\_TZ.TZ00._AC1' \
    '\_TZ.THRM._AC0'; do
    echo -n "Probing $path ... "
    echo "$path" > /proc/acpi/call 2>/dev/null || true
    result=$(cat /proc/acpi/call 2>/dev/null | tr -d '\0' || echo "N/A")
    echo "$result"
  done
else
  echo "acpi_call module not available — checking if it exists..."
  find /run/current-system/kernel-modules -name "acpi_call*" 2>/dev/null || echo "(not found)"
  echo
  echo "To install: add 'boot.extraModulePackages = [ config.boot.kernelPackages.acpi_call ];'"
  echo "Then reboot and re-run this script."
fi

echo
echo "=== ACPI tables with fan/thermal references ==="
if [ -d /sys/firmware/acpi/tables ]; then
  # Dump DSDT and search for fan-related strings
  if [ -f /sys/firmware/acpi/tables/DSDT ]; then
    echo "DSDT found, searching for fan-related methods..."
    strings /sys/firmware/acpi/tables/DSDT 2>/dev/null | grep -iE 'fan|_ac[0-9]|thrm|cool|_fst|_fsl|_fsc|_fps|predator|turbo|wmi[ad]' | sort -u | head -40
  fi
  echo
  # Check for SSDT tables too
  for ssdt in /sys/firmware/acpi/tables/SSDT*; do
    [ -f "$ssdt" ] || continue
    name=$(basename "$ssdt")
    hits=$(strings "$ssdt" 2>/dev/null | grep -ciE 'fan|thrm|cool|_fst|predator|turbo' || true)
    [ "$hits" -gt 0 ] && echo "$name: $hits fan-related strings"
  done
fi

echo
echo "=== WMI device GUIDs (known Acer mappings) ==="
echo "7A4DDFE7-... = Acer WMI (main interface, used by acer-wmi driver)"
echo "61EF69EA-... = Acer Gaming WMI (PredatorSense, turbo mode, fan control)"
echo "05901221-... = WMI BMOF (method definitions)"
echo
echo "The 61EF69EA GUID is the most likely candidate for fan control."
echo "If acpi_call is available, we can probe its methods."
