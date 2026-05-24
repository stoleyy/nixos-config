{ inputs, pkgs, ... }:

let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  programs.spicetify = {
    enable = true;
    theme = spicePkgs.themes.comfy;
    colorScheme = "custom";
    customColorScheme = {
      text = "C8CAE0";
      subtext = "B2B5CF";
      sidebar-text = "8D8FA7";
      main = "000000";
      sidebar = "07062F";
      player = "07062F";
      card = "0A094E";
      shadow = "000000";
      selected-row = "3C4B9B";
      button = "3C4B9B";
      button-active = "5987C6";
      button-disabled = "5D5E69";
      tab-active = "3C4B9B";
      notification = "324DA7";
      notification-error = "9B3C3C";
      misc = "0A094E";
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
