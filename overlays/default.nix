# Auto-import every sibling .nix file as an overlay.
# Drop a new file like `unstable.nix` in this directory and it's picked up
# automatically — no edits needed here.

{ ... }:

let
  dir = builtins.readDir ./.;
  isOverlay = name: type:
    type == "regular"
    && name != "default.nix"
    && builtins.match ".*\\.nix" name != null;
  overlayNames = builtins.filter (n: isOverlay n (dir.${n})) (builtins.attrNames dir);
in {
  nixpkgs.overlays = map (n: import (./. + "/${n}")) overlayNames;
}
