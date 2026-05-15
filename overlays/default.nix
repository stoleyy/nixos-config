# Auto-import every sibling .nix file as an overlay.
# Drop a new file like `unstable.nix` in this directory and it's picked up
# automatically — no edits needed here.

_:

let
  dir = builtins.readDir ./.;
  isOverlay =
    name: type: type == "regular" && name != "default.nix" && builtins.match ".*\\.nix" name != null;
  isStrayFile =
    name: type: type == "regular" && name != "default.nix" && builtins.match ".*\\.nix" name == null;

  names = builtins.attrNames dir;
  overlayNames = builtins.filter (n: isOverlay n dir.${n}) names;
  strayNames = builtins.filter (n: isStrayFile n dir.${n}) names;
in
if strayNames != [ ] then
  throw "overlays/: refusing to load — non-.nix file(s) present: ${toString strayNames}"
else
  {
    nixpkgs.overlays = map (n: import (./. + "/${n}")) overlayNames;
  }
