#!/usr/bin/env bash
# SessionStart hook — bootstrap Nix in this Claude Code container so the
# dev/lint harness from flake.nix (nixd, nixfmt, statix, deadnix, …) is
# runnable from chat without bouncing off CI.
#
# Idempotent: if Nix is already installed, only re-wires PATH (≪ 1 s).
# Otherwise runs the DeterminateSystems installer in container mode
# (`linux --init none --no-confirm`), then wires PATH.
#
# Optional pre-warm: set NIX_BOOTSTRAP_PREWARM=1 to realize the flake's
# devshell during bootstrap. Off by default — adds 60-180 s to the first
# session in a fresh container.
#
# Best-effort: never aborts the session. On any failure, logs and exits 0
# so the rest of SessionStart (info dump in session-start.sh) still runs.

set -uo pipefail

NIX_BIN="/nix/var/nix/profiles/default/bin/nix"
NIX_DAEMON_SH="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
NIX_SINGLE_SH="${HOME}/.nix-profile/etc/profile.d/nix.sh"
BASHRC="${HOME}/.bashrc"
MARKER_BEGIN="# >>> nix bootstrap (.claude/hooks/bootstrap-nix.sh) >>>"
MARKER_END="# <<< nix bootstrap <<<"

log() {
  printf '[bootstrap-nix %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2
}

wire_path() {
  # Source whichever Nix profile script exists from ~/.bashrc, BEFORE the
  # canonical `[[ $- != *i* ]] && return` early-exit, so non-interactive
  # bash -c invocations (how Claude Code's Bash tool runs commands) pick
  # up the PATH update too.
  mkdir -p "$(dirname "$BASHRC")"
  touch "$BASHRC"

  if grep -qF "$MARKER_BEGIN" "$BASHRC"; then
    log "bashrc already wired"
    return 0
  fi

  local tmp
  tmp="$(mktemp)" || { log "mktemp failed; PATH wiring skipped"; return 1; }

  # Heredoc with unquoted EOF: $MARKER_* and $NIX_*_SH expand here (we want
  # the literal paths written into bashrc), but \$__nix_env is escaped so it
  # ends up as a literal $__nix_env in bashrc — expansion happens there.
  {
    cat <<EOF
$MARKER_BEGIN
for __nix_env in $NIX_DAEMON_SH $NIX_SINGLE_SH; do
  if [ -e "\$__nix_env" ]; then . "\$__nix_env"; break; fi
done
unset __nix_env
$MARKER_END
EOF
    cat "$BASHRC"
  } > "$tmp"

  if mv "$tmp" "$BASHRC"; then
    log "wired Nix into $BASHRC"
  else
    log "FAILED writing to $BASHRC"
    rm -f "$tmp"
    return 1
  fi
}

install_nix() {
  log "installing Nix via DeterminateSystems installer (linux --init none)"
  # pipefail (set above) propagates the installer's exit code through the
  # `curl | sh` pipe. Installer output goes to stderr so it ends up in the
  # SessionStart hook log without polluting stdout.
  # Timeouts: 30 s to connect, 300 s total — prevents a silent hang in
  # containers with restricted egress.
  if curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
       --connect-timeout 30 --max-time 300 -L \
       https://install.determinate.systems/nix \
       | sh -s -- install linux --init none --no-confirm >&2; then
    log "Nix installed at $NIX_BIN"
    return 0
  fi
  log "Nix install FAILED — session continues without harness"
  return 1
}

prewarm() {
  if [ "${NIX_BOOTSTRAP_PREWARM:-0}" != "1" ]; then
    log "pre-warm skipped (set NIX_BOOTSTRAP_PREWARM=1 to enable)"
    return 0
  fi
  if [ ! -f flake.nix ]; then
    log "no flake.nix in cwd; pre-warm skipped"
    return 0
  fi
  log "pre-warming nix develop (60-180 s on first run)"
  if "$NIX_BIN" develop --command true >/dev/null 2>&1; then
    log "devshell realized"
  else
    log "pre-warm FAILED — first nix develop call will pay the cost lazily"
  fi
}

main() {
  if [ -x "$NIX_BIN" ]; then
    log "Nix present at $NIX_BIN"
    # Sanity-check the binary actually responds before declaring success.
    if "$NIX_BIN" --version >/dev/null 2>&1; then
      log "Nix operational: $("$NIX_BIN" --version)"
    else
      log "WARNING: $NIX_BIN exists but --version failed; Nix store may be corrupt"
    fi
    wire_path
    prewarm
    return 0
  fi
  if install_nix; then
    wire_path
    prewarm
  fi
}

main "$@"
exit 0
