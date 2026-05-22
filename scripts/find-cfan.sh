#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/tmp/acpi-ssdts"
mkdir -p "$WORKDIR"

echo "=== Decompiling all SSDTs to find CFAN EC offset ==="
for f in /sys/firmware/acpi/tables/SSDT*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  cp "$f" "$WORKDIR/${name}.dat"
  iasl -d "$WORKDIR/${name}.dat" 2>/dev/null || true
  dsl="$WORKDIR/${name}.dsl"
  [ -f "$dsl" ] || continue
  hits=$(grep -c 'CFAN' "$dsl" 2>/dev/null || echo 0)
  if [ "$hits" -gt 0 ]; then
    echo
    echo "=== $name: $hits CFAN references ==="
    grep -n -B10 -A10 'CFAN' "$dsl"
  fi
done

echo
echo "=== Searching for H_EC Field definitions with offsets ==="
for dsl in "$WORKDIR"/*.dsl; do
  [ -f "$dsl" ] || continue
  name=$(basename "$dsl")
  if grep -q 'H_EC' "$dsl" 2>/dev/null; then
    echo "--- $name: H_EC Field blocks ---"
    grep -n -A30 'Field.*ECF[23]' "$dsl" | head -100
    grep -n -A30 'Field.*ECOR' "$dsl" | head -100
  fi
done
