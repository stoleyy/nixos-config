{ colors, ... }:

{
  # Walker is a unified Wayland launcher: apps + clipboard + emoji + calc +
  # window switch + commands + websearch in one keystroke. Config and CSS
  # both live under ~/.config/walker. No HM module for walker yet — declared
  # via xdg.configFile.
  xdg.configFile = {
    "walker/config.toml".text = ''
      app_launch_prefix    = ""
      force_keyboard_focus = true
      ignore_exclusive_zones = false
      disable_click_to_close = false

      [search]
      delay        = 0
      placeholder  = "Search…"
      hide_icons   = false

      [activation_mode]
      disabled = true

      [keys]
      close   = ["Escape"]
      accept  = ["Return"]
      "list.down" = ["Down", "Tab", "ctrl+j", "ctrl+n"]
      "list.up"   = ["Up", "Shift+Tab", "ctrl+k", "ctrl+p"]

      [builtins.applications]
      weight         = 5
      context_aware  = true

      [builtins.runner]
      weight = 5

      [builtins.commands]
      weight = 5

      [builtins.calc]
      weight         = 3
      require_number = true

      [builtins.clipboard]
      weight = 5

      [builtins.emojis]
      weight = 3

      [builtins.windows]
      weight = 4

      [builtins.websearch]
      weight = 0
    '';

    # Gruvbox Dark Hard styling. Same palette + JetBrainsMono as rofi/swaync
    # so the launcher visually matches its neighbours when you toggle it.
    "walker/style.css".text = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size:   14px;
      }

      window {
        background: transparent;
        color:      ${colors.fg0};
      }

      #window {
        background:    rgba(29, 32, 33, 0.95);
        border:        1px solid rgba(152, 151, 26, 0.35);
        border-radius: 14px;
        padding:       12px;
      }

      #input {
        background:    rgba(60, 56, 54, 0.6);
        color:         ${colors.fg0};
        caret-color:   ${colors.yellow};
        border:        none;
        border-radius: 8px;
        padding:       8px 12px;
        margin-bottom: 8px;
      }

      #list, scrolledwindow {
        background: transparent;
      }

      .item {
        background:    transparent;
        color:         ${colors.fg0};
        padding:       6px 10px;
        border-radius: 8px;
        margin:        2px 0;
      }

      .item:selected,
      .item.activatable:selected {
        background: rgba(152, 151, 26, 0.35);
        color:      ${colors.fg0};
      }

      .icon {
        margin-right: 8px;
      }

      .sub {
        color:     ${colors.muted};
        font-size: 11px;
      }
    '';
  };
}
