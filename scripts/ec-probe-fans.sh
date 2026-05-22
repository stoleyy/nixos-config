#!/usr/bin/env bash
# EC register probe script for Acer Predator PO3-650 fan discovery.
# Dumps EC registers at idle, stresses CPU+GPU to force fan ramp, dumps
# again, then does BYTE-LEVEL diffs to find fan-related registers.
#
# The previous version used xxd | diff which compares 16-byte lines and
# misses individual byte changes. This version compares every single byte.
#
# Requires: debugfs=on boot param, root privileges.
set -euo pipefail

DUMP_DIR="$HOME/ec-dumps-v2"
mkdir -p "$DUMP_DIR"

echo "=== EC Fan Register Probe v2 (byte-level) ==="
echo "Output directory: $DUMP_DIR"
echo

# Ensure debugfs is mounted
if ! mountpoint -q /sys/kernel/debug 2>/dev/null; then
  echo "[*] Mounting debugfs..."
  mount -t debugfs debugfs /sys/kernel/debug
fi

# Load EC sysfs module with write support
if ! lsmod | grep -q ec_sys; then
  echo "[*] Loading ec_sys module..."
  modprobe ec_sys write_support=1
fi

EC_IO="/sys/kernel/debug/ec/ec0/io"
if [[ ! -f "$EC_IO" ]]; then
  echo "[!] ERROR: $EC_IO not found."
  echo "    Make sure you booted with 'debugfs=on' (not 'debugfs=off')."
  exit 1
fi

# Dump EC as raw binary (256 bytes)
dump_ec() {
  local label="$1"
  local outfile="$DUMP_DIR/ec_${label}.bin"
  dd if="$EC_IO" of="$outfile" bs=256 count=1 2>/dev/null
  echo "[*] Dumped EC registers -> $outfile ($(wc -c < "$outfile") bytes)"
}

# Byte-level diff: compare two binary dumps, report every byte that changed
byte_diff() {
  local file_a="$1" file_b="$2" label_a="$3" label_b="$4"
  local changes=0

  echo "Byte-level diff: $label_a -> $label_b"
  echo "OFFSET  $label_a  $label_b  DELTA"
  echo "------  ------  ------  -----"

  for offset in $(seq 0 255); do
    byte_a=$(od -An -tx1 -j "$offset" -N 1 "$file_a" 2>/dev/null | tr -d ' ')
    byte_b=$(od -An -tx1 -j "$offset" -N 1 "$file_b" 2>/dev/null | tr -d ' ')
    if [[ -n "$byte_a" && -n "$byte_b" && "$byte_a" != "$byte_b" ]]; then
      val_a=$((16#$byte_a))
      val_b=$((16#$byte_b))
      delta=$((val_b - val_a))
      printf "0x%02X    0x%02X    0x%02X    %+d (%d -> %d)\n" \
        "$offset" "$val_a" "$val_b" "$delta" "$val_a" "$val_b"
      changes=$((changes + 1))
    fi
  done

  if [[ $changes -eq 0 ]]; then
    echo "(no changes)"
  else
    echo "--- $changes byte(s) changed ---"
  fi
  echo
}

# Also record CPU temp at each sample
record_temp() {
  local label="$1"
  for tz in /sys/class/thermal/thermal_zone*/temp; do
    zone=$(basename "$(dirname "$tz")")
    type=$(cat "$(dirname "$tz")/type" 2>/dev/null || echo "unknown")
    temp=$(cat "$tz" 2>/dev/null || echo "0")
    temp_c=$((temp / 1000))
    echo "$label $zone ($type): ${temp_c}°C"
  done | tee -a "$DUMP_DIR/temps.log"
  echo
}

echo
echo "--- Phase 1: Idle baseline ---"
echo "[*] Waiting 15s for fans to settle at idle..."
sleep 15
dump_ec "01_idle"
record_temp "idle"

echo
echo "--- Phase 2: CPU stress (90s) to force fan ramp ---"
echo "[*] Spawning stress workers on all cores..."
NPROC=$(nproc)
STRESS_PIDS=()
for _ in $(seq 1 "$NPROC"); do
  yes > /dev/null &
  STRESS_PIDS+=($!)
done

# Sample EC multiple times during ramp-up
for i in 30 60 90; do
  echo "[*] Waiting until ${i}s mark..."
  sleep 30
  dump_ec "02_stress_${i}s"
  record_temp "stress_${i}s"
done

echo "[*] Killing stress workers..."
for pid in "${STRESS_PIDS[@]}"; do
  kill "$pid" 2>/dev/null || true
done
wait 2>/dev/null || true

echo
echo "--- Phase 3: Cooldown (120s) ---"
echo "[*] Letting fans spin down..."
for i in 30 60 90 120; do
  sleep 30
  dump_ec "03_cooldown_${i}s"
  record_temp "cooldown_${i}s"
done

echo
echo "=========================================="
echo "=== Phase 4: Byte-level diff results ==="
echo "=========================================="
echo

echo ">>> IDLE -> STRESS 30s <<<"
byte_diff "$DUMP_DIR/ec_01_idle.bin" "$DUMP_DIR/ec_02_stress_30s.bin" "idle" "stress30"

echo ">>> IDLE -> STRESS 60s <<<"
byte_diff "$DUMP_DIR/ec_01_idle.bin" "$DUMP_DIR/ec_02_stress_60s.bin" "idle" "stress60"

echo ">>> IDLE -> STRESS 90s (peak) <<<"
byte_diff "$DUMP_DIR/ec_01_idle.bin" "$DUMP_DIR/ec_02_stress_90s.bin" "idle" "stress90"

echo ">>> STRESS 90s (peak) -> COOLDOWN 60s <<<"
byte_diff "$DUMP_DIR/ec_02_stress_90s.bin" "$DUMP_DIR/ec_03_cooldown_60s.bin" "stress90" "cool60"

echo ">>> STRESS 90s (peak) -> COOLDOWN 120s (full) <<<"
byte_diff "$DUMP_DIR/ec_02_stress_90s.bin" "$DUMP_DIR/ec_03_cooldown_120s.bin" "stress90" "cool120"

echo ">>> IDLE -> COOLDOWN 120s (should be ~same) <<<"
byte_diff "$DUMP_DIR/ec_01_idle.bin" "$DUMP_DIR/ec_03_cooldown_120s.bin" "idle" "cool120"

echo
echo "=== Summary ==="
echo "Registers that changed BOTH during stress ramp-up AND cooldown"
echo "are almost certainly fan RPM/duty-cycle registers."
echo
echo "Cross-reference with known PO3-640 registers:"
echo "  CPU fan:  ~0x58-0x5B (target RPM hi/lo, actual RPM hi/lo)"
echo "  GPU fan:  ~0x60-0x63"
echo "  Case fan: ~0x68-0x6B"
echo
echo "All dumps saved in $DUMP_DIR"
echo "Temps logged in $DUMP_DIR/temps.log"
