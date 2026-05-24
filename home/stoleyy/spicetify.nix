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
      text = theme.stripHash c.fg0;
      subtext = theme.stripHash c.fg1;
      sidebar-text = theme.stripHash c.fg2;
      main = theme.stripHash c.black;
      sidebar = theme.stripHash c.bg1;
      player = theme.stripHash c.bg1;
      card = theme.stripHash c.bg2;
      shadow = theme.stripHash c.black;
      selected-row = theme.stripHash c.green;
      button = theme.stripHash c.green;
      button-active = theme.stripHash c.yellow;
      button-disabled = theme.stripHash c.muted;
      tab-active = theme.stripHash c.green;
      notification = theme.stripHash c.blue;
      notification-error = theme.stripHash c.red;
      misc = theme.stripHash c.bg2;
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
