#!/usr/bin/env bash
# PreCompact hook — saves session state before context compaction so the
# compacted context includes a current snapshot of the workspace.
#
# Output to stdout is injected into the compacted context by Claude Code.
# Always exit 0 — never abort compaction.
set -uo pipefail

UID_SUFFIX=$(id -u)
STATE_DIR="/tmp/.claude-session-state-${UID_SUFFIX}"
mkdir -p "$STATE_DIR"

REBUILD_GATE="/tmp/.claude-rebuild-gate-${UID_SUFFIX}"
NIX_EDITS="/tmp/.claude-nix-edits-${UID_SUFFIX}"

# --- Save git status ---
git -C /etc/nixos status --short --branch >"$STATE_DIR/git-status.txt" 2>/dev/null || true

# --- Save git diff stat ---
git -C /etc/nixos diff --stat >"$STATE_DIR/git-diff-stat.txt" 2>/dev/null || true

# --- Save rebuild gate state ---
if [ -f "$REBUILD_GATE" ]; then
  echo "present" >"$STATE_DIR/rebuild-gate.txt"
else
  echo "absent" >"$STATE_DIR/rebuild-gate.txt"
fi

# --- Output markdown summary for injection into compacted context ---
echo "## Pre-compaction session snapshot ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
echo ""

echo "### Git status (nixos-config)"
if [ -s "$STATE_DIR/git-status.txt" ]; then
  cat "$STATE_DIR/git-status.txt"
else
  echo "(no output)"
fi
echo ""

echo "### Git diff --stat"
if [ -s "$STATE_DIR/git-diff-stat.txt" ]; then
  cat "$STATE_DIR/git-diff-stat.txt"
else
  echo "(working tree clean)"
fi
echo ""

echo "### Rebuild gate"
if [ -f "$REBUILD_GATE" ]; then
  echo "READY — 'nixos-rebuild test' was run this session; 'switch' is permitted."
else
  echo "NOT READY — 'nixos-rebuild test' has not been run this session."
fi
echo ""

echo "### Nix edits tracker"
if [ -f "$NIX_EDITS" ]; then
  echo "One or more .nix files were edited this session."
else
  echo "No .nix files edited this session."
fi
echo ""

exit 0
