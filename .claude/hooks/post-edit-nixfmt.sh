#!/usr/bin/env bash
# PostToolUse hook — auto-format .nix files with nixfmt after Write/Edit.
#
# Skips silently if:
#   - the edited file is not a .nix file
#   - nixfmt is not on PATH (normal in cloud containers without nix develop)
#
# To make this hook active for every session, pre-warm the devshell:
#   set NIX_BOOTSTRAP_PREWARM=1 in .claude/settings.json env
set -uo pipefail

f=$(jq -r '.tool_input.file_path // ""')
[[ -n "$f" ]] || exit 0
[[ "$f" == *.nix ]] || exit 0
command -v nixfmt >/dev/null 2>&1 || exit 0

nixfmt "$f"
