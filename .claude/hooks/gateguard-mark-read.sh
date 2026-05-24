#!/usr/bin/env bash
# PostToolUse hook (Read) — mark .nix files as investigated for gateguard.
# When Claude reads a .nix file, create the gateguard state marker so the
# subsequent Edit/Write is not blocked.
set -uo pipefail

file_path=$(jq -r '.tool_input.file_path // ""')
[ -z "$file_path" ] && exit 0

case "$file_path" in
  *.nix) ;;
  *) exit 0 ;;
esac

STATE_DIR="/tmp/.claude-gateguard-$(id -u)"
mkdir -p "$STATE_DIR"
path_hash=$(printf '%s' "$file_path" | md5sum | cut -d' ' -f1)
touch "$STATE_DIR/$path_hash"
exit 0
