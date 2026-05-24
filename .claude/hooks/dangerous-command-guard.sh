#!/usr/bin/env bash
# PreToolUse hook (Bash) — blocks dangerous shell commands before they execute.
#
# Exit 2 = block the tool call (Claude Code interprets this as a hard stop).
# Exit 0 = allow.
#
# Patterns blocked:
#   rm -rf /          (wipe root)
#   git push --force  (force-push anywhere)
#   git reset --hard
#   git push <remote> main  (direct push to main)
#   curl/wget piped to bash or sh
#   --no-verify flag
set -uo pipefail

cmd=$(jq -r '.tool_input.command // ""')

if [ -z "$cmd" ]; then
  exit 0
fi

# rm -rf / (absolute root path, with or without trailing slash)
if echo "$cmd" | grep -qE 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+/\s*$|rm\s+-[a-zA-Z]*f[a-zA-Z]*r\s+/\s*$|rm\s+-rf\s+/\b|rm\s+-fr\s+/\b'; then
  echo "BLOCKED: 'rm -rf /' is not allowed." >&2
  exit 2
fi

# git push --force (anywhere in the command)
if echo "$cmd" | grep -qE 'git\s+push\b.*--force\b|git\s+push\b.*-f\b'; then
  echo "BLOCKED: 'git push --force' is not allowed." >&2
  exit 2
fi

# git reset --hard
if echo "$cmd" | grep -qE 'git\s+reset\b.*--hard\b'; then
  echo "BLOCKED: 'git reset --hard' is not allowed." >&2
  exit 2
fi

# git push directly to main branch
if echo "$cmd" | grep -qE 'git\s+push\b.*\bmain\b'; then
  echo "BLOCKED: Direct 'git push ... main' is not allowed. Use a PR workflow." >&2
  exit 2
fi

# curl | bash or curl | sh
if echo "$cmd" | grep -qE 'curl\b.*\|\s*(bash|sh)\b'; then
  echo "BLOCKED: Piping curl output to a shell is not allowed." >&2
  exit 2
fi

# wget | bash or wget | sh
if echo "$cmd" | grep -qE 'wget\b.*\|\s*(bash|sh)\b'; then
  echo "BLOCKED: Piping wget output to a shell is not allowed." >&2
  exit 2
fi

# --no-verify flag (skips git hooks or SSL verification)
if echo "$cmd" | grep -qE '\-\-no-verify\b'; then
  echo "BLOCKED: '--no-verify' is not allowed." >&2
  exit 2
fi

exit 0
