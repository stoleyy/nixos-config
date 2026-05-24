# Pin Hyprland to 0.52.0 so plugins (also 0.52.0 in nixpkgs) can load.
# Remove this overlay once nixpkgs updates hyprlandPlugins to 0.52.1+.
_: prev: {
  hyprland = prev.hyprland.overrideAttrs (old: {
    version = "0.52.0";
    src = prev.fetchFromGitHub {
      owner = "hyprwm";
      repo = "hyprland";
      fetchSubmodules = true;
      tag = "v0.52.0";
      hash = "sha256-Sqp8L7RPpO0MGIgVZSo1QkgPw9/vCIxpq4hfz6PTPsk=";
    };
    # Match the version info shown by `hyprctl version`.
    TAG = "v0.52.0";
  });
}
