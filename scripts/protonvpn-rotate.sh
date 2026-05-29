#!@bash@/bin/bash
# ProtonVPN quality-based server rotation.
# Checks current connection health; only rotates if degraded.
# Injected at build time: path, poolFile, hysteresis, killswitch tables.

set -euo pipefail
export PATH="@path@:$PATH"

POOL_FILE="@poolFile@"
IFACE="protonvpn"
HYSTERESIS=@hysteresis@
PING_COUNT=3
PING_TIMEOUT=2
MAX_LATENCY_MS=150
MAX_LOSS_PCT=20

if [ ! -f "$POOL_FILE" ]; then
  echo "ERROR: server pool not found at $POOL_FILE" >&2
  echo "See: docs/protonvpn-wg-setup.md for how to populate it." >&2
  exit 1
fi

SERVER_COUNT=$(jq length "$POOL_FILE")
if [ "$SERVER_COUNT" -lt 2 ]; then
  echo "Pool has fewer than 2 servers, nothing to rotate." >&2
  exit 0
fi

# Current peer info
CURRENT_KEY=$(wg show "$IFACE" peers 2>/dev/null | head -1)
CURRENT_ENDPOINT=$(wg show "$IFACE" endpoints 2>/dev/null | awk '{print $2}')

if [ -z "$CURRENT_KEY" ]; then
  echo "ERROR: no active peer on $IFACE — tunnel may be down" >&2
  exit 1
fi

CURRENT_IP=${CURRENT_ENDPOINT%%:*}
echo "Current: $CURRENT_ENDPOINT (key: ${CURRENT_KEY:0:8}...)"

# --- Quality check ---
CURRENT_PING=$(ping -c 5 -W 3 -q 10.2.0.1 2>/dev/null \
  | awk -F'/' '/^rtt/{found=1; print $5} END{if(!found) print "99999"}')
CURRENT_LOSS=$(ping -c 5 -W 3 -q 10.2.0.1 2>/dev/null \
  | awk -F'[,%]' '/packet loss/{found=1; gsub(/ /,"",$3); print $3; exit} END{if(!found) print "100"}')

CURRENT_PING_INT=${CURRENT_PING%.*}
CURRENT_LOSS_INT=${CURRENT_LOSS%.*}
echo "Quality: latency=${CURRENT_PING_INT}ms loss=${CURRENT_LOSS_INT}%"

if [ "$CURRENT_PING_INT" -lt "$MAX_LATENCY_MS" ] && [ "$CURRENT_LOSS_INT" -lt "$MAX_LOSS_PCT" ]; then
  echo "Connection healthy (${CURRENT_PING_INT}ms, ${CURRENT_LOSS_INT}% loss). No rotation needed."
  exit 0
fi

echo "Connection degraded! Searching for a better server..."

# --- Measure latency to each pool server ---
BEST_NAME="" BEST_IP="" BEST_PORT="" BEST_KEY=""
BEST_LATENCY=99999 CURRENT_LATENCY=99999

while IFS= read -r server; do
  name=$(echo "$server" | jq -r '.name')
  endpoint=$(echo "$server" | jq -r '.endpoint')
  key=$(echo "$server" | jq -r '.publicKey')
  ip=${endpoint%%:*}
  port=${endpoint##*:}

  avg=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" -q "$ip" 2>/dev/null \
    | awk -F'/' '/^rtt/{found=1; print $5} END{if(!found) print "99999"}')

  echo "  $name ($ip): ${avg}ms"

  if [ "$ip" = "$CURRENT_IP" ]; then
    CURRENT_LATENCY=${avg%.*}
  fi

  avg_int=${avg%.*}
  if [ "$avg_int" -lt "$BEST_LATENCY" ] 2>/dev/null; then
    BEST_LATENCY=$avg_int
    BEST_NAME=$name BEST_IP=$ip BEST_PORT=$port BEST_KEY=$key
  fi
done < <(jq -c '.[]' "$POOL_FILE")

if [ -z "$BEST_KEY" ] || [ "$BEST_LATENCY" = "99999" ]; then
  echo "No reachable server found, keeping current." >&2
  exit 0
fi

if [ "$BEST_KEY" = "$CURRENT_KEY" ]; then
  echo "Current server is already the fastest ($BEST_NAME, ${BEST_LATENCY}ms). No swap needed."
  exit 0
fi

DIFF=$((CURRENT_LATENCY - BEST_LATENCY))
if [ "$DIFF" -lt "$HYSTERESIS" ]; then
  echo "Best ($BEST_NAME, ${BEST_LATENCY}ms) is not ${HYSTERESIS}ms+ faster than current (${CURRENT_LATENCY}ms). Keeping current."
  exit 0
fi

echo "Swapping to $BEST_NAME ($BEST_IP:$BEST_PORT, ${BEST_LATENCY}ms, delta=${DIFF}ms)..."

# Step 1: Allow BOTH endpoints during transition
nft -f - <<NFTEOF
@killswitchBoth@
NFTEOF

# Step 2: Atomic peer swap
wg set "$IFACE" peer "$CURRENT_KEY" remove
wg set "$IFACE" peer "$BEST_KEY" \
  endpoint "$BEST_IP:$BEST_PORT" \
  allowed-ips "0.0.0.0/0,::/0" \
  persistent-keepalive 25

# Step 3: Wait for handshake (up to 10s)
HANDSHAKE_OK=false
for _ in $(seq 1 20); do
  HS=$(wg show "$IFACE" latest-handshakes | awk '{print $2}')
  if [ -n "$HS" ] && [ "$HS" != "0" ]; then
    HANDSHAKE_OK=true
    break
  fi
  sleep 0.5
done

if [ "$HANDSHAKE_OK" = "false" ]; then
  echo "WARNING: No handshake after 10s. Rolling back..." >&2
  wg set "$IFACE" peer "$BEST_KEY" remove
  wg set "$IFACE" peer "$CURRENT_KEY" \
    endpoint "$CURRENT_IP:${CURRENT_ENDPOINT##*:}" \
    allowed-ips "0.0.0.0/0,::/0" \
    persistent-keepalive 25
  nft -f - <<NFTEOF
@killswitchCurrent@
NFTEOF
  echo "Rolled back to $CURRENT_ENDPOINT." >&2
  exit 1
fi

# Step 4: Finalize kill switch with only the new endpoint
nft -f - <<NFTEOF
@killswitchBest@
NFTEOF

echo "Done. Now connected to $BEST_NAME ($BEST_IP:$BEST_PORT)."
