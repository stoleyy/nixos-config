#!/usr/bin/env bash
set -euo pipefail

echo "=== THERMAL ZONES + TRIP POINTS ==="
for tz in /sys/class/thermal/thermal_zone*/; do
  type=$(cat "${tz}type" 2>/dev/null || echo "?")
  temp=$(cat "${tz}temp" 2>/dev/null || echo "0")
  temp_c=$((temp / 1000))
  echo "--- $(basename "$tz") ($type) = ${temp_c}°C ---"
  for tp in "${tz}"trip_point_*_temp; do
    [ -f "$tp" ] || continue
    tp_name=$(basename "$tp")
    tp_type_file="${tp%_temp}_type"
    tp_type=$(cat "$tp_type_file" 2>/dev/null || echo "?")
    tp_val=$(cat "$tp" 2>/dev/null || echo "0")
    tp_c=$((tp_val / 1000))
    writable="ro"
    [ -w "$tp" ] && writable="RW"
    echo "  $tp_name: ${tp_c}°C ($tp_type) [$writable]"
  done
done

echo
echo "=== I2C BUSES ==="
ls /dev/i2c-* 2>/dev/null || echo "(none)"

echo
echo "=== I2C DEVICE SCAN (bus 0) ==="
if command -v i2cdetect &>/dev/null; then
  i2cdetect -y 0 2>/dev/null || echo "(scan failed or bus 0 unavailable)"
else
  echo "(i2cdetect not installed — need i2c-tools)"
fi

echo
echo "=== ACPI FAN -> THERMAL ZONE BINDING ==="
for cd in /sys/class/thermal/cooling_device*/; do
  type=$(cat "${cd}type" 2>/dev/null || echo "?")
  [[ "$type" == "Fan" ]] || continue
  name=$(basename "$cd")
  cur=$(cat "${cd}cur_state" 2>/dev/null || echo "?")
  max=$(cat "${cd}max_state" 2>/dev/null || echo "?")
  echo "$name: type=$type cur=$cur max=$max"
  # Check which thermal zones reference this cooling device
  for tz in /sys/class/thermal/thermal_zone*/; do
    for cdev in "${tz}"cdev*/; do
      [ -d "$cdev" ] || continue
      if [ -L "${cdev%/}" ]; then
        target=$(readlink "${cdev%/}" 2>/dev/null || echo "?")
        [[ "$target" == *"$name"* ]] && echo "  -> bound to $(basename "$tz")"
      fi
    done
  done
done

echo
echo "=== ACPI METHODS (fan-related) ==="
if [ -d /sys/bus/acpi/devices ]; then
  for dev in /sys/bus/acpi/devices/*/; do
    name=$(basename "$dev")
    case "$name" in
      *FAN*|*THM*|*TZ*) echo "$dev -> $name";;
    esac
  done
fi

echo
echo "=== WMI DEVICE DETAILS ==="
for wmi in /sys/bus/wmi/devices/*/; do
  guid=$(basename "$wmi")
  driver=$(readlink "${wmi}driver" 2>/dev/null || echo "unbound")
  echo "$guid driver=$driver"
done
