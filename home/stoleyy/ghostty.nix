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
      # JetBrainsMono ligatures (on by default) — kept explicit so intent is clear.
      font-feature = "calt";
      window-padding-x = 12;
      window-padding-y = 12;
      window-decoration = false;
      window-save-state = "always";
      mouse-hide-while-typing = true;
      # 10M lines of scrollback, copy selections straight to the clipboard,
      # and make detected URLs clickable.
      scrollback-limit = 10000000;
      copy-on-select = "clipboard";
      link-url = true;
      confirm-close-surface = false;
      # Fish shell integration: jump-to-prompt, sudo cache, window title.
      shell-integration = "fish";
      shell-integration-features = "cursor,sudo,title";
      keybind = [
        # Splits (ctrl+shift won't collide with Hyprland's $mod binds)
        "ctrl+shift+enter=new_split:right"
        "ctrl+shift+down=new_split:down"
        "ctrl+shift+w=close_surface"
        "ctrl+shift+h=goto_split:left"
        "ctrl+shift+l=goto_split:right"
        "ctrl+shift+k=goto_split:up"
        "ctrl+shift+j=goto_split:down"
        "ctrl+shift+z=toggle_split_zoom"
        # Font zoom + config reload
        "ctrl+plus=increase_font_size:1"
        "ctrl+minus=decrease_font_size:1"
        "ctrl+zero=reset_font_size"
        "ctrl+shift+r=reload_config"
      ];
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
