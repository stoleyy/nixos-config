{ theme, ... }:

let
  inherit (theme) colors font;
in
{
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "sanctuary";
      background-opacity = 0.85;
      background-blur-radius = 20;
      cursor-style = "bar";
      cursor-style-blink = false;
      font-family = font.name;
      font-size = font.size;
      window-padding-x = 12;
      window-padding-y = 12;
      window-decoration = false;
      mouse-hide-while-typing = true;
    };
    themes.sanctuary = {
      background = colors.bg0;
      foreground = colors.fg0;
      selection-background = colors.bg2;
      selection-foreground = colors.fg0;
      cursor-color = colors.yellow;
      palette = [
        "0=${colors.black}"
        "1=${colors.red}"
        "2=${colors.green}"
        "3=${colors.yellow}"
        "4=${colors.blue}"
        "5=${colors.purple}"
        "6=${colors.aqua}"
        "7=${colors.fg1}"
        "8=${colors.muted}"
        "9=${colors.bright.red}"
        "10=${colors.bright.green}"
        "11=${colors.bright.yellow}"
        "12=${colors.bright.blue}"
        "13=${colors.bright.purple}"
        "14=${colors.bright.aqua}"
        "15=${colors.fg0}"
      ];
    };
  };
}
