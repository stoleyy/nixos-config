#!/usr/bin/env python3
"""Build a ProtonVPN WireGuard server pool from the GUI's cached server list.

The ProtonVPN GUI app caches the full server list (with WireGuard keys) at:
  ~/.var/app/com.protonvpn.www/cache/Proton/VPN/serverlist.json

This script reads that cache, filters by country/tier/features, and writes
server-pool.json for the protonvpn-rotate systemd service.

No API authentication needed — just keep the GUI logged in occasionally
so the cache stays fresh.

Usage:
  protonvpn-fetch-pool --country US --output /var/lib/protonvpn/server-pool.json
"""

import argparse
import json
import os
import sys
from pathlib import Path

# Possible cache locations (flatpak, native, snap)
CACHE_PATHS = [
    Path.home() / ".var/app/com.protonvpn.www/cache/Proton/VPN/serverlist.json",
    Path.home() / ".cache/Proton/VPN/serverlist.json",
    Path("/home") / os.environ.get("SUDO_USER", "") / ".var/app/com.protonvpn.www/cache/Proton/VPN/serverlist.json",
    Path("/home") / os.environ.get("SUDO_USER", "") / ".cache/Proton/VPN/serverlist.json",
]


def find_cache() -> Path:
    for p in CACHE_PATHS:
        if p.exists() and p.stat().st_size > 0:
            return p
    return None


def main():
    parser = argparse.ArgumentParser(description="Build ProtonVPN WireGuard server pool from GUI cache")
    parser.add_argument("--country", "-c", default="US", help="Exit country code (default: US)")
    parser.add_argument("--tier", "-t", type=int, default=2, help="Max tier: 0=free, 1=basic, 2=plus (default: 2)")
    parser.add_argument("--p2p", action="store_true", help="Only include P2P-capable servers")
    parser.add_argument("--top", type=int, default=10, help="Keep top N servers by score (default: 10)")
    parser.add_argument("--output", "-o", default="/var/lib/protonvpn/server-pool.json", help="Output path")
    parser.add_argument("--cache", help="Override cache file path")
    args = parser.parse_args()

    cache_path = Path(args.cache) if args.cache else find_cache()
    if not cache_path or not cache_path.exists():
        print("ERROR: ProtonVPN GUI server cache not found.", file=sys.stderr)
        print("Searched:", file=sys.stderr)
        for p in CACHE_PATHS:
            print(f"  {p}", file=sys.stderr)
        print("\nOpen the ProtonVPN GUI and log in to populate the cache.", file=sys.stderr)
        sys.exit(1)

    with open(cache_path) as f:
        data = json.load(f)

    servers = data.get("LogicalServers", [])
    print(f"Cache: {cache_path} ({len(servers)} servers)", file=sys.stderr)

    filtered = []
    for srv in servers:
        if args.country and srv.get("ExitCountry", "").upper() != args.country.upper():
            continue
        if srv.get("Tier", 0) > args.tier:
            continue
        # Features bitmask: 4 = P2P
        if args.p2p and not (srv.get("Features", 0) & 4):
            continue

        for phys in srv.get("Servers", []):
            if phys.get("Status") != 1:
                continue
            entry_ip = phys.get("EntryIP")
            x25519_key = phys.get("X25519PublicKey")
            if not entry_ip or not x25519_key:
                continue

            filtered.append({
                "name": srv.get("Name", "unknown"),
                "endpoint": f"{entry_ip}:51820",
                "publicKey": x25519_key,
                "score": srv.get("Score", 999),
                "load": srv.get("Load", 100),
                "city": srv.get("City", ""),
            })
            break  # one physical per logical

    # Sort by score (lower = better)
    filtered.sort(key=lambda x: x["score"])
    print(f"Matched: {len(filtered)} servers ({args.country}, tier<={args.tier})", file=sys.stderr)

    # Deduplicate by endpoint IP — multiple logical servers can share an IP,
    # which makes rotation pointless for latency. Keep the best-scored one per IP.
    seen_ips = set()
    deduped = []
    for s in filtered:
        ip = s["endpoint"].split(":")[0]
        if ip not in seen_ips:
            seen_ips.add(ip)
            deduped.append(s)
    filtered = deduped
    print(f"Unique endpoints: {len(filtered)}", file=sys.stderr)

    # Keep top N
    filtered = filtered[:args.top]

    pool = [{"name": s["name"], "endpoint": s["endpoint"], "publicKey": s["publicKey"]}
            for s in filtered]

    if not pool:
        print("ERROR: No servers matched filters. Pool not updated.", file=sys.stderr)
        sys.exit(1)

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    tmp_path = args.output + ".tmp"
    old_umask = os.umask(0o177)
    try:
        with open(tmp_path, "w") as f:
            json.dump(pool, f, indent=2)
        os.replace(tmp_path, args.output)
    finally:
        os.umask(old_umask)

    print(f"\nWrote {len(pool)} servers to {args.output}:", file=sys.stderr)
    for s in filtered:
        print(f"  {s['name']:12s} {s['endpoint']:22s} load={s['load']}% score={s['score']:.2f} ({s['city']})", file=sys.stderr)


if __name__ == "__main__":
    main()
