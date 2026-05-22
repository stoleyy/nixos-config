#!/usr/bin/env bash
# Test direct EC register write for fan control
# EC offset 0x0E = 0x64 (100) — suspected fan duty cycle
set -euo pipefail

EC_IO="/sys/kernel/debug/ec/ec0/io"

if [ ! -f "$EC_IO" ]; then
  echo "EC io not found — need ec_sys with write_support=1"
  exit 1
fi

read_ec() {
  local offset=$1
  od -An -tx1 -j "$offset" -N 1 "$EC_IO" | tr -d ' '
}

write_ec() {
  local offset=$1
  local value=$2
  printf "\\x$(printf '%02x' "$value")" | dd of="$EC_IO" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null
}

echo "=== Current EC fan-related registers ==="
echo "0x0E: 0x$(read_ec 14) (suspected fan duty %)"
echo "0x0F: 0x$(read_ec 15)"
echo "0x10: 0x$(read_ec 16)"
echo "0x12: 0x$(read_ec 18) (CFAN value)"
echo "0x18: 0x$(read_ec 24) (temp sensor 1)"
echo "0x19: 0x$(read_ec 25) (temp sensor 2)"

echo
echo "=== Test: Write 0x32 (50%) to EC offset 0x0E ==="
echo "LISTEN for fan speed change..."
echo -n "Old value at 0x0E: 0x"
read_ec 14

write_ec 14 50  # 0x32 = 50

echo -n "New value at 0x0E: 0x"
read_ec 14

echo
echo "Waiting 5 seconds — listen for fan change..."
sleep 5

echo -n "Value at 0x0E after 5s: 0x"
read_ec 14

echo
echo "=== Restoring 0x0E to 0x64 (100%) ==="
write_ec 14 100  # 0x64 = 100

echo -n "Restored value: 0x"
read_ec 14

echo
echo "If the fan briefly slowed down at the 50% step, we found the register!"
echo "If nothing changed, 0x0E is not the fan duty cycle."
