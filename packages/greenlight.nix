{ pkgs }:
let
  base = pkgs.appimageTools.wrapType2 {
    pname = "greenlight";
    version = "2.4.1";
    src = pkgs.fetchurl {
      url = "https://github.com/unknownskl/greenlight/releases/download/v2.4.1/Greenlight-2.4.1.AppImage";
      hash = "sha256-CYf0BCkQB4ms9bj9fPgEgdjHA/JvKaCxgC6wb7/bc1c=";
    };
  };
in
pkgs.symlinkJoin {
  name = "greenlight";
  paths = [ base ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/greenlight \
      --add-flags "--ozone-platform=wayland" \
      --add-flags "--use-gl=angle" \
      --add-flags "--use-angle=opengl"
  '';
}
