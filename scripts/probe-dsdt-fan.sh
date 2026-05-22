#!/usr/bin/env bash
# Deep probe of DSDT/SSDT for fan control methods on Acer Predator PO3-650
set -euo pipefail

echo "=== DSDT fan-related strings (full) ==="
strings /sys/firmware/acpi/tables/DSDT 2>/dev/null | grep -iE 'fan|_ac[0-9]|thrm|cool|_fst|_fsl|_fsc|_fps|cfan|sfnv|gfns|turbo|wmid|wmi[12]|predator|_q[0-9a-f]{2}' | sort -u

echo
echo "=== SSDT7 fan-related strings (full) ==="
strings /sys/firmware/acpi/tables/SSDT7 2>/dev/null | sort -u | head -80

echo
echo "=== All SSDT tables: fan strings ==="
for ssdt in /sys/firmware/acpi/tables/SSDT*; do
  [ -f "$ssdt" ] || continue
  name=$(basename "$ssdt")
  echo "--- $name ---"
  strings "$ssdt" 2>/dev/null | grep -iE 'fan|cfan|sfnv|gfns|cool|thrm|turbo|_fst|_ac[0-9]|predator' | sort -u || echo "(none)"
done

echo
echo "=== EC-related ACPI paths in DSDT ==="
strings /sys/firmware/acpi/tables/DSDT 2>/dev/null | grep -iE 'h_ec|ec0|lpcb.*ec|ecrd|ecwr|ecmd' | sort -u

echo
echo "=== Full DSDT method listing (first 100) ==="
# iasl can decompile DSDT but might not be installed; try strings approach
strings /sys/firmware/acpi/tables/DSDT 2>/dev/null | grep -E '^[A-Z_][A-Z0-9_]{3}$' | sort -u | head -100
