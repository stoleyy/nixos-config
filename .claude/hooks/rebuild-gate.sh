#!/usr/bin/env bash
# PreToolUse hook (Bash) — gates 'nixos-rebuild switch' behind a prior
# 'nixos-rebuild test' within the same session.
#
# State file: /tmp/.claude-rebuild-gate-<uid>
#   Present  = test was run this session; switch is permitted (one-shot).
#   Absent   = test not yet run; switch is blocked.
#
# Exit 2 = block. Exit 0 = allow.
set -uo pipefail

cmd=$(jq -r '.tool_input.command // ""')

if [ -z "$cmd" ]; then
  exit 0
fi

STATE_FILE="/tmp/.claude-rebuild-gate-$(id -u)"

# Track nix edits state file path for anti-rationalization hook
NIX_EDITS_FILE="/tmp/.claude-nix-edits-$(id -u)"

# When 'nixos-rebuild test' is seen, mark state as ready for switch
if echo "$cmd" | grep -qE 'nixos-rebuild\s+test\b'; then
  touch "$STATE_FILE"
  # Also record that a test was run (clears the anti-rationalization trigger)
  touch "$NIX_EDITS_FILE.tested"
  exit 0
fi

# When 'nixos-rebuild switch' is seen, require prior test
if echo "$cmd" | grep -qE 'nixos-rebuild\s+switch\b'; then
  if [ ! -f "$STATE_FILE" ]; then
    echo "BLOCKED: Run 'nixos-rebuild test --flake .#predator' first to validate before switching." >&2
    exit 2
  fi
  # One-shot: remove gate so a second switch in the same session is blocked again
  rm -f "$STATE_FILE"
  exit 0
fi

exit 0
