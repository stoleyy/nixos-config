{
  inputs,
  pkgs,
  theme,
  ...
}:

let
  inherit (theme) colors stripHash;
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  programs.spicetify = {
    enable = true;
    theme = spicePkgs.themes.comfy;
    colorScheme = "custom";
    customColorScheme = {
      text = stripHash colors.fg0;
      subtext = stripHash colors.fg1;
      sidebar-text = stripHash colors.fg2;
      main = stripHash colors.black;
      sidebar = stripHash colors.bg1;
      player = stripHash colors.bg1;
      card = stripHash colors.bg2;
      shadow = stripHash colors.black;
      selected-row = stripHash colors.green;
      button = stripHash colors.green;
      button-active = stripHash colors.yellow;
      button-disabled = stripHash colors.muted;
      tab-active = stripHash colors.green;
      notification = stripHash colors.blue;
      notification-error = stripHash colors.red;
      misc = stripHash colors.bg2;
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
