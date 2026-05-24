#!/usr/bin/env bash
# Temporarily allow all pool server IPs through the kill switch so the
# rotation script can ping them. Runtime-dynamic because the pool IP
# list comes from a JSON file. Base rules mirror lib/nftables.nix.
# Injected at build time: @path@, @poolFile@

set -euo pipefail
export PATH="@path@:$PATH"

POOL_FILE="@poolFile@"
[ -f "$POOL_FILE" ] || exit 0

CURRENT_IP=$(wg show protonvpn endpoints 2>/dev/null | awk -F'[:\t]' '{print $2}')
[ -z "$CURRENT_IP" ] && exit 1

ALLOW_RULES="ip daddr $CURRENT_IP accept"
for ip in $(jq -r '.[].endpoint' "$POOL_FILE" | cut -d: -f1 | sort -u); do
  ALLOW_RULES="$ALLOW_RULES
      ip daddr $ip accept"
done

nft -f - <<PROBEEOF
table inet protonvpn_killswitch {
  chain output {
    type filter hook output priority -100; policy accept;
    oifname "lo" accept
    ip daddr 192.168.1.0/24 accept
    ip daddr 169.254.0.0/16 accept
    ip daddr 224.0.0.0/4 accept
    ip daddr 255.255.255.255 accept
    ip6 daddr fe80::/10 accept
    ip6 daddr ff00::/8 accept
    $ALLOW_RULES
    oifname "protonvpn" accept
    counter drop
  }
}
PROBEEOF
