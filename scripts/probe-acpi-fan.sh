#!/usr/bin/env bash
# Probe ACPI methods for fan control using acpi_call
set -euo pipefail

if [ ! -f /proc/acpi/call ]; then
  echo "Loading acpi_call module..."
  modprobe acpi_call || { echo "FATAL: acpi_call not available"; exit 1; }
fi

acpi_call() {
  local method="$1"
  echo "$method" > /proc/acpi/call 2>/dev/null
  local result
  result=$(cat /proc/acpi/call 2>/dev/null | tr -d '\0')
  echo "$result"
}

echo "=== Probing EC fan methods ==="
echo

# The DSDT shows \_SB.PC00.LPCB.H_EC.CFAN
# Try reading it (no args = read)
echo -n "\_SB.PC00.LPCB.H_EC.CFAN: "
acpi_call "\_SB.PC00.LPCB.H_EC.CFAN"

# Try EC read/command methods
echo -n "\_SB.PC00.LPCB.H_EC.ECRD: "
acpi_call "\_SB.PC00.LPCB.H_EC.ECRD"

echo -n "\_SB.PC00.LPCB.H_EC.ECNT: "
acpi_call "\_SB.PC00.LPCB.H_EC.ECNT"

echo
echo "=== Probing thermal zone fan methods ==="

# _FST returns fan status (speed in RPM)
for tz in "" "0" "1" "2" "3" "4" "5" "6" "7" "8"; do
  path="\_TZ.TZ0${tz}._FST"
  echo -n "$path: "
  acpi_call "$path" 2>/dev/null || echo "(invalid)"
done

# Try thermal zones directly
for i in "" 0 1 2 3 4 5; do
  for method in _AC0 _AC1 _AC2 _AC3 _AC4 _TMP _CRT; do
    path="\_TZ.TZ0${i}.${method}"
    result=$(acpi_call "$path" 2>/dev/null)
    [[ "$result" == *"Error"* || -z "$result" ]] && continue
    echo "$path: $result"
  done
done

echo
echo "=== Probing FAN objects ==="
# FAN0-FAN4 from SSDT7
for i in 0 1 2 3 4; do
  echo -n "\_TZ.FAN${i}._STA: "
  acpi_call "\_TZ.FAN${i}._STA"

  echo -n "\_TZ.FAN${i}._FST: "
  acpi_call "\_TZ.FAN${i}._FST"
done

echo
echo "=== Probing WMID methods ==="
# WMID = WMI Device, used by PredatorSense
# WMAA = WMI ACPI Adapter (standard method name)
echo -n "\_SB.WMID.WMAA 0x1 0x1 0x0: "
acpi_call "\_SB.WMID.WMAA 0x1 0x1 0x0"

# Try various WMI method IDs
# PredatorSense uses WMID.WMAA with different function codes
for func in 0x1 0x2 0x3 0x4 0x5 0x6 0x7 0x8 0x9 0xa; do
  result=$(acpi_call "\_SB.WMID.WMAA 0x0 $func 0x0" 2>/dev/null)
  [[ "$result" == *"Error"* ]] && continue
  echo "\_SB.WMID.WMAA 0x0 $func 0x0: $result"
done

echo
echo "=== Probing CVF (Current Value Fan) ==="
for i in 0 1 2 3 4; do
  echo -n "\_TZ.CVF${i}: "
  acpi_call "\_TZ.CVF${i}"
done

echo
echo "=== Probing FMT (Fan Mode/Throttle) ==="
for i in 0 1 2 3 4; do
  echo -n "\_TZ.FMT${i}: "
  acpi_call "\_TZ.FMT${i}"
done

echo
echo "=== Probing FNCL (Fan Control Level) ==="
echo -n "\_TZ.FNCL: "
acpi_call "\_TZ.FNCL"

echo
echo "=== Probing EC query methods (fan events) ==="
for q in _Q11 _Q12 _Q13 _Q14 _Q15 _Q16 _Q17 _Q18 _Q19 _Q20 _Q21; do
  echo -n "\_SB.PC00.LPCB.H_EC.$q: "
  acpi_call "\_SB.PC00.LPCB.H_EC.$q"
done

echo
echo "=== Decompile SSDT8 (fan speed/duty cycle) ==="
if command -v iasl &>/dev/null; then
  cp /sys/firmware/acpi/tables/SSDT8 /tmp/ssdt8.dat
  iasl -d /tmp/ssdt8.dat 2>/dev/null
  if [ -f /tmp/ssdt8.dsl ]; then
    echo "--- SSDT8 decompiled (fan-related sections) ---"
    grep -A5 -iE 'fan|duty|speed|cfan' /tmp/ssdt8.dsl | head -60
  fi
else
  echo "(iasl not installed yet — rebuild first)"
fi
