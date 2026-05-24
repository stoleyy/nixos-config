#!/usr/bin/env bash
# UserPromptSubmit hook — scans the user's prompt for secrets before Claude
# processes it.  Blocks (exit 2) if a secret pattern is detected.
#
# Patterns:
#   AGE secret keys          AGE-SECRET-KEY-[A-Z0-9]+
#   PEM private keys         -----BEGIN * PRIVATE KEY-----
#   GitHub tokens            ghp_[A-Za-z0-9]{36}
#   Anthropic tokens         sk-ant-[A-Za-z0-9-]{90,}
#   OpenAI tokens            sk-[A-Za-z0-9]{48,}
#   WireGuard private keys   "private key" label followed by base64
set -uo pipefail

prompt=$(jq -r '.user_prompt // ""')

if [ -z "$prompt" ]; then
  exit 0
fi

# AGE secret key
if echo "$prompt" | grep -qE 'AGE-SECRET-KEY-[A-Z0-9]+'; then
  echo "BLOCKED: Prompt contains an AGE secret key." >&2
  exit 2
fi

# PEM private key block
if echo "$prompt" | grep -qE '\-\-\-\-\-BEGIN [A-Z ]* PRIVATE KEY\-\-\-\-\-'; then
  echo "BLOCKED: Prompt contains a PEM private key block." >&2
  exit 2
fi

# GitHub personal access token
if echo "$prompt" | grep -qE 'ghp_[A-Za-z0-9]{36}'; then
  echo "BLOCKED: Prompt contains a GitHub personal access token (ghp_...)." >&2
  exit 2
fi

# Anthropic API token
if echo "$prompt" | grep -qP 'sk-ant-[A-Za-z0-9\-]{90,}' 2>/dev/null \
  || echo "$prompt" | grep -qE 'sk-ant-[A-Za-z0-9-]{90,}'; then
  echo "BLOCKED: Prompt contains an Anthropic API token (sk-ant-...)." >&2
  exit 2
fi

# OpenAI API token (sk- followed by 48+ alphanumeric chars, not sk-ant-)
if echo "$prompt" | grep -qE 'sk-[A-Za-z0-9]{48,}' && ! echo "$prompt" | grep -qE 'sk-ant-'; then
  echo "BLOCKED: Prompt appears to contain an OpenAI API token (sk-...)." >&2
  exit 2
fi

# WireGuard private key: "private key" (case-insensitive) near a base64 blob
# WireGuard keys are 44-char base64 strings (256-bit + padding)
if echo "$prompt" | grep -qiE 'private.?key' && echo "$prompt" | grep -qE '[A-Za-z0-9+/]{43}='; then
  echo "BLOCKED: Prompt appears to contain a WireGuard private key." >&2
  exit 2
fi

exit 0
