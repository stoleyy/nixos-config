#!/usr/bin/env bash
# SessionStart hook — reports repo state up-front so every Claude session
# starts with the same picture without burning tool calls on discovery.
set -euo pipefail

echo "=== stoleyy/nixos-config — session start ==="
echo

echo "## Branch / status"
git status --short --branch | head -20
echo

echo "## Last 5 commits"
git log --oneline -5
echo

echo "## Flake inputs (resolved revs)"
if command -v nix >/dev/null 2>&1 && [ -f flake.lock ]; then
  nix flake metadata --json 2>/dev/null \
    | jq -r '.locks.nodes | to_entries[] | select(.value.locked) | "\(.key): \(.value.locked.rev // .value.locked.ref // "n/a") (\(.value.locked.lastModified // 0 | strftime("%Y-%m-%d")))"' 2>/dev/null \
    | head -20
else
  echo "(nix not on PATH or flake.lock missing)"
fi
echo

echo "## Reminders"
echo "- Active flake on this system is /etc/nixos (this clone is a workspace)."
echo "- Rebuild:  cd /etc/nixos && sudo git pull origin main && sudo nixos-rebuild switch --flake .#predator"
echo "- Validate: nix develop -c nix flake check"
echo "- Plasma is the default SDDM session; Hyprland is selectable as fallback."
if command -v nix >/dev/null 2>&1; then
  echo "- Harness available this session: $(nix --version)"
else
  echo "- Harness NOT available — bootstrap-nix.sh exited without putting nix on PATH (see hook log above)."
fi
echo "==========================================="
