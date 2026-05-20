#!/usr/bin/env bash
# Idempotent provisioning for the Prowlarr + Sonarr + Radarr stack.
# Wires Sonarr and Radarr into Prowlarr's Apps integration and bulk-adds
# the common public-tracker indexers. Safe to re-run — anything already
# configured is skipped.
#
# Usage:
#   sudo bash scripts/setup-arr-stack.sh
#
# Prereqs:
#   - prowlarr, sonarr, radarr services running (systemctl is-active <name>)
#   - first-run wizard has been touched at least once in each app so a
#     config.xml exists under /var/lib/<app>/ (the API key is generated
#     on first start, independent of any admin password you set)
#   - jq and curl on PATH (use `nix-shell -p jq curl --run '...'` if not)
#
# Private trackers are NOT included by design — those need your own
# credentials. After this script runs, add them in the Prowlarr UI at
# http://localhost:9696/.

set -euo pipefail

readonly PROWLARR_URL="${PROWLARR_URL:-http://localhost:9696}"
readonly SONARR_URL="${SONARR_URL:-http://localhost:8989}"
readonly RADARR_URL="${RADARR_URL:-http://localhost:7878}"

# Public indexers to add. Names must match Prowlarr's indexer schema
# exactly (case-sensitive). Edit this list to taste before running.
readonly PUBLIC_INDEXERS=(
  "1337x"
  "The Pirate Bay"
  "EZTV"
  "Nyaa.si"
  "LimeTorrents"
  "TheRARBG"
  "YTS"
  "TorrentGalaxy"
)

# ── 0. Sanity ────────────────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] || { echo "Run as root (config.xml files are root-readable only)." >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found. Try: nix-shell -p jq curl --run 'sudo bash $0'" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl not found." >&2; exit 1; }

log()  { printf '%-6s %s\n' "[$1]" "$2"; }

# ── 1. Discover API keys ─────────────────────────────────────────────────────

find_api_key() {
  local app="$1"
  local cfg
  cfg=$(find "/var/lib/$app" -maxdepth 4 -name config.xml -type f 2>/dev/null | head -1)
  [[ -n "$cfg" ]] || { echo "No config.xml under /var/lib/$app — has $app started yet?" >&2; return 1; }
  grep -oP '(?<=<ApiKey>)[^<]+' "$cfg" | head -1
}

log INFO "Reading API keys from /var/lib/{prowlarr,sonarr,radarr}/"
PROWLARR_KEY=$(find_api_key prowlarr)
SONARR_KEY=$(find_api_key sonarr)
RADARR_KEY=$(find_api_key radarr)

# ── 2. Reachability check ────────────────────────────────────────────────────

for pair in "prowlarr:$PROWLARR_URL" "sonarr:$SONARR_URL" "radarr:$RADARR_URL"; do
  name="${pair%%:*}"; url="${pair#*:}"
  if ! curl -fsS -m 5 -o /dev/null "$url/api/v3/system/status" 2>/dev/null \
    && ! curl -fsS -m 5 -o /dev/null "$url/api/v1/system/status" 2>/dev/null \
    && ! curl -fsS -m 5 -o /dev/null "$url" 2>/dev/null; then
    echo "Cannot reach $name at $url. Is the service running?" >&2
    exit 1
  fi
done

# ── 3. Prowlarr API helpers ──────────────────────────────────────────────────

pq_get()  { curl -fsS -H "X-Api-Key: $PROWLARR_KEY" "$PROWLARR_URL/api/v1$1"; }
pq_post() { curl -fsS -H "X-Api-Key: $PROWLARR_KEY" -H 'Content-Type: application/json' -X POST -d "$2" "$PROWLARR_URL/api/v1$1"; }

# ── 4. Register Sonarr / Radarr as Prowlarr Apps ─────────────────────────────

register_app() {
  local impl="$1" name="$2" url="$3" key="$4"

  local existing
  existing=$(pq_get /applications | jq -r --arg n "$name" '.[] | select(.name == $n) | .id')
  if [[ -n "$existing" ]]; then
    log SKIP "app $name already registered (id=$existing)"
    return
  fi

  local schema
  schema=$(pq_get /applications/schema | jq --arg i "$impl" '.[] | select(.implementation == $i)')
  if [[ -z "$schema" || "$schema" == "null" ]]; then
    log FAIL "no schema for application '$impl' in Prowlarr"
    return
  fi

  local payload
  payload=$(jq -n \
    --argjson s "$schema" \
    --arg name "$name" \
    --arg base "$url" \
    --arg key  "$key" \
    --arg pwl  "$PROWLARR_URL" '
      $s + {
        name: $name,
        syncLevel: "fullSync",
        tags: [],
        fields: ($s.fields | map(
          if .name == "baseUrl"     then .value = $base
          elif .name == "apiKey"    then .value = $key
          elif .name == "prowlarrUrl" then .value = $pwl
          else . end))
      }')

  if pq_post /applications "$payload" >/dev/null; then
    log ADD  "app $name → $url"
  else
    log FAIL "could not register app $name"
  fi
}

log INFO "Wiring Sonarr and Radarr into Prowlarr → Apps"
register_app "Sonarr" "Sonarr" "$SONARR_URL" "$SONARR_KEY"
register_app "Radarr" "Radarr" "$RADARR_URL" "$RADARR_KEY"

# ── 5. Add public indexers ───────────────────────────────────────────────────

add_indexer() {
  local name="$1"

  local existing
  existing=$(pq_get /indexer | jq -r --arg n "$name" '.[] | select(.name == $n) | .id')
  if [[ -n "$existing" ]]; then
    log SKIP "indexer $name already added"
    return
  fi

  local schema
  schema=$(pq_get /indexer/schema | jq --arg n "$name" '.[] | select(.name == $n)')
  if [[ -z "$schema" || "$schema" == "null" ]]; then
    log WARN "indexer $name not in Prowlarr schema — name may have changed upstream"
    return
  fi

  local payload
  payload=$(echo "$schema" | jq '. + {enable: true, priority: 25, tags: []}')

  if pq_post /indexer "$payload" >/dev/null; then
    log ADD  "indexer $name"
  else
    log FAIL "indexer $name"
  fi
}

log INFO "Adding public indexers"
for idx in "${PUBLIC_INDEXERS[@]}"; do
  add_indexer "$idx"
done

# ── 6. Push to Sonarr/Radarr ─────────────────────────────────────────────────

log INFO "Triggering Prowlarr → Sonarr/Radarr indexer sync"
pq_post /command '{"name":"ApplicationIndexerSync"}' >/dev/null
log INFO "Sync queued — indexers should appear in Sonarr/Radarr in ~10s."

cat <<EOF

Done. Verify:
  - Prowlarr: $PROWLARR_URL  → Indexers tab should list what was added
  - Sonarr:   $SONARR_URL    → Settings → Indexers (synced from Prowlarr)
  - Radarr:   $RADARR_URL    → Settings → Indexers (synced from Prowlarr)

Private trackers: add in Prowlarr UI (Indexers → Add → search tracker name).
Once added, the same ApplicationIndexerSync above (or any change in
Prowlarr) propagates them to Sonarr/Radarr automatically.

Re-run this script any time — it is idempotent.
EOF
