# PrismLauncher gaming integration: the `minecraft` command alias.
#
# nixpkgs builds `prismlauncher` with `symlinkJoin`, whose builder runs
# `buildCommand` (honouring `postBuild`) and never the `postInstall`/`postBuild`
# hooks added via `overrideAttrs`. So the old `overrideAttrs { postInstall =
# ln -s … }` was a silent no-op and the `minecraft` alias never existed. A real
# nested symlinkJoin with `postBuild` creates it correctly, with the
# glfw3-minecraft LD_LIBRARY_PATH wrapper from the inner derivation intact.
#
# The two runtime fixes for Minecraft on this NVIDIA + Wayland box live
# elsewhere, deliberately NOT in a launcher wrapper:
#   - native Wayland GLFW (the ~8 fps fix) + earlyWindowControl=false →
#     packages/prism-gaming-setup.nix
#   - __GL_THREADED_OPTIMIZATIONS=0 (the NoVizFallback "EGL: Failed to clear
#     current context" window-init crash) → modules/nvidia.nix (session-wide,
#     Hyprland) + packages/gamescope-session.nix (gamer/Gaming-Mode).
# It is session-scoped rather than wrapper-baked because PrismLauncher is
# single-instance (QLocalSocket): a stale launcher daemon spawns the Minecraft
# JVM, so an env var set only on the wrapped binary would be missed on exactly
# the launches that crash. Setting it in the session environment makes every
# descendant inherit it regardless of launch path (`minecraft`, the .desktop
# entry, or the Steam shortcut).
final: prev: {
  prismlauncher = prev.symlinkJoin {
    name = "prismlauncher-${prev.prismlauncher.version}";
    paths = [ prev.prismlauncher ];
    postBuild = ''
      ln -s $out/bin/prismlauncher $out/bin/minecraft
    '';
    # symlinkJoin doesn't carry meta; keep it so `mainProgram`, the desktop
    # entry and `nix run` still resolve `prismlauncher`.
    meta = prev.prismlauncher.meta // {
      mainProgram = "prismlauncher";
    };
  };

  prism-gaming-setup = final.callPackage ../packages/prism-gaming-setup.nix { };
}
