#!/usr/bin/env bash
# Stop hook — sends a desktop notification when Claude Code finishes a response.
#
# Requires notify-send and an active Wayland or X display.
# Always exit 0 — never fail the session.
set -uo pipefail

# Require notify-send
if ! command -v notify-send >/dev/null 2>&1; then
  exit 0
fi

# Require an active display (Wayland preferred, X fallback)
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  exit 0
fi

notify-send \
  -a "Claude Code" \
  -u normal \
  "Claude Code" \
  "Response complete" \
  2>/dev/null || true

exit 0
