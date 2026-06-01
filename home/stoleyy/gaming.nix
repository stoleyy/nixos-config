# Desktop-session (stoleyy) PrismLauncher gaming setup.
#
# Runs prism-gaming-setup on every activation (idempotent): enables PrismLauncher's
# native Wayland GLFW — the fix for Minecraft's ~8 fps software-render through the
# -glamor-off XWayland (modules/hyprland.nix) — and registers the Steam Non-Steam
# shortcut so it's launchable from Steam Big Picture in the Hyprland session.
#
# The same tool runs for the low-priv `gamer` account from the gaming-tuned
# gamescope-session (packages/gamescope-session.nix); the two accounts keep
# separate PrismLauncher data dirs by design (W1/W2 untrusted-code containment).
#
# Caveat (same class as the qBittorrent seed): PrismLauncher rewrites its cfg on
# clean exit and Steam rewrites shortcuts.vdf on exit, so a change made while
# either is running is clobbered. This converges at the next login/rebuild when
# they're closed. If a fresh box hasn't logged into Steam yet, the shortcut step
# is a no-op until userdata exists, then lands on the next activation.
{ pkgs, lib, ... }:

{
  home.activation.prismGamingSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.prism-gaming-setup}/bin/prism-gaming-setup || true
  '';
}
