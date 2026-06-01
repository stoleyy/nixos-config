# Wire PrismLauncher for gaming on this NVIDIA + Hyprland box.
#
# Two jobs, both idempotent and keyed off the runtime $HOME so the SAME tool
# serves stoleyy (desktop session) and the low-priv `gamer` account (gaming-tuned
# session) — which have separate PrismLauncher data dirs by design:
#
#   1. Flip PrismLauncher's `UseNativeGLFW=true`. nixpkgs already puts the
#      Wayland-patched `glfw3-minecraft` on the launcher's LD_LIBRARY_PATH, and
#      PrismLauncher auto-detects it (dlopen + dlinfo). With the flag on it adds
#      `-Dorg.lwjgl.glfw.libname=<that lib>` to the Minecraft JVM ONLY (not the
#      Java probe), so LWJGL loads the native GLFW and GLFW selects its Wayland
#      backend (WAYLAND_DISPLAY is set in both sessions). Minecraft then presents
#      via native Wayland instead of the `-glamor off` XWayland (modules/hyprland.nix)
#      that falls back to llvmpipe software rendering — the ~8 fps → full-rate fix.
#      This is the OpenGL/LWJGL analogue of PROTON_ENABLE_WAYLAND=1 for Proton.
#
#   2. Register PrismLauncher as a Non-Steam shortcut so it shows up in Steam Big
#      Picture / the gaming-tuned (gamer) Gaming-Mode session. Mirrors the
#      shortcuts.vdf writer in packages/game-install.nix.
{
  writeShellApplication,
  writers,
  python3Packages,
  prismlauncher,
  coreutils,
  gnugrep,
  gnused,
}:
let
  # Standalone Non-Steam shortcut writer. EXE/NAME are baked at build time;
  # the Steam user id and shortcuts.vdf are resolved at runtime from $HOME.
  addShortcut =
    writers.writePython3Bin "prism-steam-shortcut"
      {
        libraries = [ python3Packages.vdf ];
        flakeIgnore = [ "E501" ]; # allow long lines (store paths, dict literals)
      }
      ''
        import binascii
        import ctypes
        import os
        import sys

        import vdf

        EXE = "${prismlauncher}/bin/prismlauncher"
        NAME = "PrismLauncher"
        START_DIR = "${prismlauncher}/bin/"
        LAUNCH_OPTIONS = ""

        userdata = os.path.expanduser("~/.local/share/Steam/userdata")
        if not os.path.isdir(userdata):
            print("prism-steam-shortcut: no Steam userdata yet — log into Steam once, then re-run.", file=sys.stderr)
            sys.exit(0)

        profiles = [d for d in os.listdir(userdata) if d.isdigit() and d != "0" and os.path.isdir(os.path.join(userdata, d))]
        if not profiles:
            print("prism-steam-shortcut: no Steam profile under userdata/ — skipping shortcut.", file=sys.stderr)
            sys.exit(0)

        # AppID formula matching Steam's internal non-Steam game calculation.
        crc = binascii.crc32(f'"{EXE}"{NAME}'.encode("utf-8")) & 0xFFFFFFFF
        appid = ctypes.c_int32(crc | 0x80000000).value

        for sid in profiles:
            path = os.path.join(userdata, sid, "config", "shortcuts.vdf")
            if os.path.exists(path):
                with open(path, "rb") as f:
                    data = vdf.binary_loads(f.read())
            else:
                data = {"shortcuts": {}}

            shortcuts = data.get("shortcuts", {})

            # Idempotent: skip if already registered under this name.
            if any(entry.get("AppName") == NAME for entry in shortcuts.values()):
                print(f"prism-steam-shortcut: already present for profile {sid}", file=sys.stderr)
                continue

            next_idx = str(max((int(k) for k in shortcuts.keys()), default=-1) + 1)
            shortcuts[next_idx] = {
                "appid": appid,
                "AppName": NAME,
                "Exe": '"' + EXE + '"',
                "StartDir": '"' + START_DIR + '"',
                "icon": "",
                "ShortcutPath": "",
                "LaunchOptions": LAUNCH_OPTIONS,
                "IsHidden": 0,
                "AllowDesktopConfig": 1,
                "AllowOverlay": 1,
                "OpenVR": 0,
                "Devkit": 0,
                "DevkitGameID": "",
                "DevkitOverrideAppID": 0,
                "LastPlayTime": 0,
                "FlatpakAppID": "",
                "tags": {},
            }
            data["shortcuts"] = shortcuts

            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(vdf.binary_dumps(data))
            print(f"prism-steam-shortcut: added to profile {sid} (appid={appid})", file=sys.stderr)
      '';
in
writeShellApplication {
  name = "prism-gaming-setup";
  runtimeInputs = [
    addShortcut
    coreutils
    gnugrep
    gnused
  ];
  text = ''
    # 1. Enable native (Wayland-patched) GLFW — the ~8 fps software-render fix.
    #    PrismLauncher rewrites this cfg on clean exit; this seed only takes
    #    effect on its NEXT launch, so it converges at the next login/rebuild
    #    when the launcher is closed (same caveat as the qBittorrent seed).
    data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
    cfg="$data_home/PrismLauncher/prismlauncher.cfg"
    mkdir -p "$(dirname "$cfg")"
    touch "$cfg"
    if grep -q '^UseNativeGLFW=' "$cfg"; then
      sed -i 's/^UseNativeGLFW=.*/UseNativeGLFW=true/' "$cfg"
    elif grep -q '^\[General\]' "$cfg"; then
      sed -i '/^\[General\]/a UseNativeGLFW=true' "$cfg"
    else
      printf '[General]\nUseNativeGLFW=true\n' >> "$cfg"
    fi

    # 2. Register the Steam Non-Steam shortcut (no-op if Steam isn't set up yet).
    prism-steam-shortcut || true
  '';
}
