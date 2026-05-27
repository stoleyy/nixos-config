# Deployment identity — single source of truth for user, paths, and mount points.
# Passed to all system modules via specialArgs (see lib/default.nix).
rec {
  user = "stoleyy";
  home = "/home/${user}";
  gamesDir = "${home}/games";
  mediaDir = "${gamesDir}/media";
  dataDir = "/data";
  # Primary display output — used by hyprland, gamescope, wallpaper engine.
  monitor = "DP-2";
  # IPC flag: GameMode touches this to signal nvidia-undervolt to unlock clocks.
  # Kept in /run/gamemode (tmpfs) — correct lifetime for IPC; survives neither reboots nor crashes.
  gamemodeFlagFile = "/run/gamemode/gpu-unlock";
}
