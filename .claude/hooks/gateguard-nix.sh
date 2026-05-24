#!/usr/bin/env bash
# PreToolUse hook (Edit|Write) — fact-forcing gate for .nix files.
#
# On the FIRST Edit/Write to any .nix file in a session, block and instruct
# Claude to investigate the file first.  On subsequent attempts to the same
# file, allow (investigation already done).
#
# State dir: /tmp/.claude-gateguard-<uid>/
#   One empty file per already-investigated path (named by md5sum of path).
#
# Exit 2 = block (first access). Exit 0 = allow (already investigated).
set -uo pipefail

# Extract file path from either Edit or Write tool input shapes
file_path=$(jq -r '.tool_input.file_path // .tool_input.filePath // ""')

if [ -z "$file_path" ]; then
  exit 0
fi

# Only gate .nix files
case "$file_path" in
  *.nix) ;;
  *) exit 0 ;;
esac

STATE_DIR="/tmp/.claude-gateguard-$(id -u)"
mkdir -p "$STATE_DIR"

# Use md5sum of the path as a safe, unique filename
path_hash=$(printf '%s' "$file_path" | md5sum | cut -d' ' -f1)
state_marker="$STATE_DIR/$path_hash"

if [ -f "$state_marker" ]; then
  # Already investigated this session — allow the edit
  exit 0
fi

# First access — mark as investigated and block with instructions
touch "$state_marker"

echo "PAUSED: Before editing '$file_path', read and understand the file first." >&2
echo "Use the Read tool on '$file_path', then retry your Edit/Write." >&2
exit 2
