{ theme, ... }:

let
  c = theme.colors;
  f = theme.font;
in
{
  programs.ghostty = {
    enable = true;
    settings = {
      background = c.bg0;
      foreground = c.fg0;
      selection-background = c.bg2;
      selection-foreground = c.fg0;
      palette = "0=${c.black},1=${c.red},2=${c.green},3=${c.yellow},4=${c.blue},5=${c.purple},6=${c.aqua},7=${c.fg1},8=${c.muted},9=${c.bright.red},10=${c.bright.green},11=${c.bright.yellow},12=${c.bright.blue},13=${c.bright.purple},14=${c.bright.aqua},15=${c.fg0}";
      background-opacity = 0.85;
      background-blur-radius = 20;
      cursor-style = "bar";
      cursor-style-blink = false;
      cursor-color = c.yellow;
      font-family = f.name;
      font-size = f.size;
      window-padding-x = 12;
      window-padding-y = 12;
      window-decoration = false;
      mouse-hide-while-typing = true;
    };
  };
}
