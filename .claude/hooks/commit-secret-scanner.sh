#!/usr/bin/env bash
# PreToolUse hook (Bash) — scans staged changes for secrets before any
# 'git commit' executes.  Only fires when the command is a git commit.
#
# Scans lines beginning with '+' in 'git diff --cached' output (added lines).
# Exit 2 = block. Exit 0 = allow.
set -uo pipefail

cmd=$(jq -r '.tool_input.command // ""')

if [ -z "$cmd" ]; then
  exit 0
fi

# Only intercept git commit commands
if ! echo "$cmd" | grep -qE 'git\s+commit\b'; then
  exit 0
fi

# Capture added lines from staged diff
added=$(git diff --cached 2>/dev/null | grep '^+' | grep -v '^+++') || added=""

if [ -z "$added" ]; then
  exit 0
fi

# AGE secret key
if echo "$added" | grep -qE 'AGE-SECRET-KEY-[A-Z0-9]+'; then
  echo "BLOCKED: Staged changes contain an AGE secret key." >&2
  exit 2
fi

# PEM private key block
if echo "$added" | grep -qE '\-\-\-\-\-BEGIN [A-Z ]* PRIVATE KEY\-\-\-\-\-'; then
  echo "BLOCKED: Staged changes contain a PEM private key block." >&2
  exit 2
fi

# GitHub personal access token
if echo "$added" | grep -qE 'ghp_[A-Za-z0-9]{36}'; then
  echo "BLOCKED: Staged changes contain a GitHub personal access token (ghp_...)." >&2
  exit 2
fi

# Anthropic API token
if echo "$added" | grep -qE 'sk-ant-[A-Za-z0-9-]{90,}'; then
  echo "BLOCKED: Staged changes contain an Anthropic API token (sk-ant-...)." >&2
  exit 2
fi

# OpenAI API token (sk- followed by 48+ alphanumeric, not sk-ant-)
if echo "$added" | grep -qE 'sk-[A-Za-z0-9]{48,}' && ! echo "$added" | grep -qE 'sk-ant-'; then
  echo "BLOCKED: Staged changes appear to contain an OpenAI API token (sk-...)." >&2
  exit 2
fi

# WireGuard private key: label near base64 blob
if echo "$added" | grep -qiE 'private.?key' && echo "$added" | grep -qE '[A-Za-z0-9+/]{43}='; then
  echo "BLOCKED: Staged changes appear to contain a WireGuard private key." >&2
  exit 2
fi

exit 0
