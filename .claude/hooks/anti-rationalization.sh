#!/usr/bin/env bash
# Stop hook — warns if .nix files were edited this session but
# 'nixos-rebuild test' was never run.
#
# Cannot block (Stop hooks are advisory only) — always exit 0.
# Warning is printed to stdout so it appears in the session transcript.
set -uo pipefail

NIX_EDITS_FILE="/tmp/.claude-nix-edits-$(id -u)"
REBUILD_GATE="/tmp/.claude-rebuild-gate-$(id -u)"

# Edits tracked but test gate never set → validation was skipped
if [ -f "$NIX_EDITS_FILE" ] && [ ! -f "$REBUILD_GATE" ]; then
  echo ""
  echo "WARNING: .nix files were edited this session but 'nixos-rebuild test' has not been run."
  echo "Validation pipeline (CLAUDE.md):"
  echo "  1. nix flake check --no-build"
  echo "  2. nixos-rebuild dry-build --flake .#predator"
  echo "  3. sudo nixos-rebuild test --flake .#predator"
  echo "  4. systemctl --failed && journalctl -p err -b 0"
  echo "  5. sudo nixos-rebuild switch --flake .#predator  (only after step 4 is clean)"
  echo ""
fi

exit 0
