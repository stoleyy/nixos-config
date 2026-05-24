# Deltarune Sanctuary — centralized theme definition.
# Single source of truth for colors, font, and sizing across all modules.
# Passed to HM modules via extraSpecialArgs: { theme, ... }
{
  font = {
    name = "JetBrainsMono Nerd Font";
    size = 13;
  };

  # Strip the leading "#" from a hex color string: "#C8CAE0" → "C8CAE0"
  # Use in contexts that need bare hex (rgba(), Spicetify, etc.)
  stripHash = color: builtins.substring 1 6 color;

  # Convert "#RRGGBB" to [R G B] integer list for Chromium theme JSON
  hexToRgb =
    hex:
    let
      h = builtins.substring 1 6 hex;
    in
    [
      (builtins.fromTOML "v=0x${builtins.substring 0 2 h}").v
      (builtins.fromTOML "v=0x${builtins.substring 2 2 h}").v
      (builtins.fromTOML "v=0x${builtins.substring 4 2 h}").v
    ];

  colors = {
    bg0 = "#000000";
    bg1 = "#07062F";
    bg2 = "#0A094E";
    fg0 = "#C8CAE0";
    fg1 = "#B2B5CF";
    fg2 = "#8D8FA7";
    muted = "#5D5E69";
    red = "#9B3C3C";
    green = "#3C4B9B";
    yellow = "#5987C6";
    blue = "#324DA7";
    purple = "#3C4B9B";
    aqua = "#5987C6";
    orange = "#304B72";
    bright = {
      red = "#B06060";
      green = "#5987C6";
      yellow = "#8D8FA7";
      blue = "#B2B5CF";
      purple = "#8D8FA7";
      aqua = "#5987C6";
      orange = "#3C4B9B";
    };
    black = "#000000";
    black2 = "#07062F";
  };
}
