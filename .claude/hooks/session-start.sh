#!/usr/bin/env bash
# SessionStart hook — reports repo state up-front so every Claude session
# starts with the same picture without burning tool calls on discovery.
#
# Uses set -uo (not -e) so a failed sub-command never aborts the whole report.
set -uo pipefail

echo "=== stoleyy/nixos-config — session start ==="
echo

echo "## Branch / status"
git status --short --branch | head -20
echo

# Highlight a dirty working tree so Claude notices before proposing edits.
dirty=$(git status --porcelain | wc -l)
if [ "$dirty" -gt 0 ]; then
  echo "!! $dirty uncommitted change(s) in working tree"
  echo
fi

echo "## Last 5 commits"
git log --oneline -5
echo

# Warn about .backup orphans — the most common HM rebuild blocker (CLAUDE.md pitfall).
# These accumulate in HOME when a previous HM activation failed mid-flight.
backup_files=$(find "${HOME}" -maxdepth 4 -name "*.backup" 2>/dev/null | head -10)
if [ -n "$backup_files" ]; then
  echo "!! HM .backup orphan(s) found — remove before rebuilding on the live system:"
  echo "$backup_files"
  echo
fi

echo "## Flake inputs (resolved revs)"
if command -v nix >/dev/null 2>&1 && [ -f flake.lock ]; then
  nix flake metadata --json 2>/dev/null \
    | jq -r '
        .locks.nodes
        | to_entries[]
        | select(.value.locked)
        | "\(.key): \(.value.locked.rev // .value.locked.ref // "n/a") (\(.value.locked.lastModified // 0 | strftime("%Y-%m-%d")))"
      ' 2>/dev/null \
    | sort \
    | head -20 \
    || echo "(flake metadata parse failed)"
else
  echo "(nix not on PATH or flake.lock missing)"
fi
echo

echo "## Harness"
if command -v nix >/dev/null 2>&1; then
  echo "- nix: $(nix --version)"
  echo "- nixfmt on PATH: $(command -v nixfmt 2>/dev/null || echo 'no (run: nix develop)')"
  echo "- statix  on PATH: $(command -v statix  2>/dev/null || echo 'no (run: nix develop)')"
else
  echo "- Harness NOT available — bootstrap-nix.sh exited without putting nix on PATH (see hook log above)."
fi
echo

echo "## Reminders"
echo "- Active flake on this system is /etc/nixos (this clone is a workspace)."
echo "- Rebuild:  cd /etc/nixos && sudo git pull origin main && sudo nixos-rebuild switch --flake .#predator"
echo "- Validate: nix flake check --no-build  →  nixos-rebuild dry-build --flake .#predator"
echo "- Plasma is the default SDDM session; Hyprland is selectable as fallback."
echo "==========================================="
