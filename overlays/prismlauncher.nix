# PrismLauncher gaming integration.
#
# 1. `minecraft` command alias. The upstream-style `postInstall` symlink trick
#    used previously in modules/gaming.nix was a silent no-op: nixpkgs builds
#    `prismlauncher` with `symlinkJoin`, whose builder runs `buildCommand`
#    (honouring `postBuild`) and never the `postInstall`/`postBuild` hooks added
#    via `overrideAttrs`. So `minecraft` never existed. A real nested symlinkJoin
#    with `postBuild` creates it correctly (verified: `minecraft` -> wrapped
#    prismlauncher, with the glfw3-minecraft LD_LIBRARY_PATH wrapper intact).
#
# 2. `prism-gaming-setup` — enables native Wayland GLFW (the 8 fps fix) and adds
#    the Steam Non-Steam shortcut. See packages/prism-gaming-setup.nix.
final: prev: {
  prismlauncher = prev.symlinkJoin {
    name = "prismlauncher-${prev.prismlauncher.version}";
    paths = [ prev.prismlauncher ];
    nativeBuildInputs = [ prev.makeWrapper ];
    postBuild = ''
      # Bake __GL_THREADED_OPTIMIZATIONS=0 into the launcher so the Minecraft JVM
      # it spawns inherits it on every launch path (the `minecraft`/`prismlauncher`
      # command, the .desktop entry, the Steam shortcut). With native-Wayland GLFW
      # (prism-gaming-setup's UseNativeGLFW) + NVIDIA's EGL, Minecraft's
      # multi-threaded GL context handoff crashes window creation ("GLFW error
      # 65544: EGL: Failed to clear current context"); disabling the driver's
      # threaded optimisations makes the handoff synchronous. REQUIRED in addition
      # to earlyWindowControl=false (packages/prism-gaming-setup.nix): that clears
      # the early-display crash, this clears the NoVizFallback handoff crash that
      # earlyWindowControl=false then exposes. --set-default so a per-launch
      # override still wins.
      rm $out/bin/prismlauncher
      makeWrapper ${prev.prismlauncher}/bin/prismlauncher $out/bin/prismlauncher \
        --set-default __GL_THREADED_OPTIMIZATIONS 0
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
