# Gamescope session launcher — diagnostic logging + libEGL fix + steam-gamescope.
# Used by the gaming-tuned specialisation's greetd session.
{
  writeShellScript,
  libglvnd,
  host,
}:
writeShellScript "gamescope-session" ''
  # Thorough logging — survives reboots since it's in $HOME.
  LOG=${host.home}/gamescope-session.log
  exec > "$LOG" 2>&1
  set -x

  echo "============================================"
  echo "gamescope session — $(date)"
  echo "============================================"

  echo "--- environment ---"
  env | sort

  echo "--- DRI devices ---"
  ls -la /dev/dri/ || true

  echo "--- logind session ---"
  loginctl session-status || true

  echo "--- seat info ---"
  loginctl seat-status seat0 || true

  echo "--- DRM info ---"
  for card in /sys/class/drm/card*/; do
    echo "$card: $(cat "$card/device/vendor" 2>/dev/null) $(cat "$card/device/device" 2>/dev/null)"
  done

  echo "--- NVIDIA driver ---"
  cat /proc/driver/nvidia/version 2>/dev/null || true

  echo "--- steam-gamescope wrapper contents ---"
  cat "$(command -v steam-gamescope)" || true

  echo "--- gamescope version ---"
  gamescope --help 2>&1 | head -1 || true

  # Xwayland EGL fix: libepoxy does dlopen("libEGL.so.1") at runtime
  # but has no RPATH. Xwayland's RUNPATH includes libglvnd, but
  # RUNPATH is NOT inherited by transitive dlopen calls. Prepend
  # libglvnd + the OpenGL driver dir so the GLVND EGL dispatcher
  # and NVIDIA vendor ICD are discoverable.
  export LD_LIBRARY_PATH="${libglvnd}/lib:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

  echo "============================================"
  echo "Launching steam-gamescope..."
  echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
  echo "============================================"

  steam-gamescope
  RC=$?
  echo "steam-gamescope exited with code $RC at $(date)"
  exit $RC
''
