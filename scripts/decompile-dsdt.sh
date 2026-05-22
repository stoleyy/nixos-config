#!/usr/bin/env bash
# Decompile DSDT and find CFAN field definition
set -euo pipefail

WORKDIR="/tmp/acpi-dsdt"
mkdir -p "$WORKDIR"

echo "=== Decompiling DSDT ==="
cp /sys/firmware/acpi/tables/DSDT "$WORKDIR/dsdt.dat"
iasl -d "$WORKDIR/dsdt.dat" 2>/dev/null

if [ ! -f "$WORKDIR/dsdt.dsl" ]; then
  echo "FATAL: decompilation failed"
  exit 1
fi

echo "=== CFAN definition ==="
grep -n -B5 -A10 'CFAN' "$WORKDIR/dsdt.dsl" | head -80

echo
echo "=== EC OperationRegion definition ==="
grep -n -B2 -A15 'OperationRegion.*EC' "$WORKDIR/dsdt.dsl" | head -80

echo
echo "=== EC Field definitions containing CFAN ==="
# Find the Field block that contains CFAN and show surrounding fields
grep -n 'CFAN' "$WORKDIR/dsdt.dsl" | while read -r line; do
  linenum=$(echo "$line" | cut -d: -f1)
  # Show 30 lines before and 5 after to capture the Field() block
  sed -n "$((linenum-30)),$((linenum+5))p" "$WORKDIR/dsdt.dsl"
  echo "---"
done

echo
echo "=== Full DSDT saved to $WORKDIR/dsdt.dsl ==="
echo "Lines: $(wc -l < "$WORKDIR/dsdt.dsl")"
