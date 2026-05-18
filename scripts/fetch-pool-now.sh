#!/usr/bin/env bash
set -euo pipefail
exec python3 /etc/nixos/scripts/protonvpn-fetch-pool.py \
  --country US \
  --top 10 \
  --output /var/lib/protonvpn/server-pool.json
