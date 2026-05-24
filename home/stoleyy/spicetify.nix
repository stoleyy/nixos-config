{
  inputs,
  pkgs,
  theme,
  ...
}:

let
  c = theme.colors;
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  programs.spicetify = {
    enable = true;
    theme = spicePkgs.themes.comfy;
    colorScheme = "custom";
    customColorScheme = {
      text = builtins.substring 1 6 c.fg0;
      subtext = builtins.substring 1 6 c.fg1;
      sidebar-text = builtins.substring 1 6 c.fg2;
      main = builtins.substring 1 6 c.black;
      sidebar = builtins.substring 1 6 c.bg1;
      player = builtins.substring 1 6 c.bg1;
      card = builtins.substring 1 6 c.bg2;
      shadow = builtins.substring 1 6 c.black;
      selected-row = builtins.substring 1 6 c.green;
      button = builtins.substring 1 6 c.green;
      button-active = builtins.substring 1 6 c.yellow;
      button-disabled = builtins.substring 1 6 c.muted;
      tab-active = builtins.substring 1 6 c.green;
      notification = builtins.substring 1 6 c.blue;
      notification-error = builtins.substring 1 6 c.red;
      misc = builtins.substring 1 6 c.bg2;
    };
    enabledExtensions = with spicePkgs.extensions; [
      adblock
      hidePodcasts
      shuffle
      fullAppDisplay
      keyboardShortcut
      # Synced lyrics in a poppable miniplayer; spicetify-cli built-in.
      popupLyrics
    ];
    enabledCustomApps = with spicePkgs.apps; [
      lyricsPlus
      newReleases
    ];
  };
}
