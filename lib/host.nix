# Deployment identity — single source of truth for user, paths, and mount points.
# Passed to all system modules via specialArgs (see lib/default.nix).
rec {
  user = "stoleyy";
  home = "/home/${user}";
  gamesDir = "${home}/games";
  mediaDir = "${gamesDir}/media";
  dataDir = "/data";
}
