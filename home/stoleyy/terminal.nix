_:

{
  programs.kitty = {
    enable = true;
    themeFile = "gruvbox-dark-hard";
    font.name = "JetBrainsMono Nerd Font";
    font.size = 13;
    settings = {
      enable_audio_bell = false;
      confirm_os_window_close = 0;
      scrollback_lines = 10000;
      # Window chrome
      window_padding_width = 12;
      hide_window_decorations = true;
      # Opacity for blur-through with Hyprland
      background_opacity = "0.85";
      # Tab bar
      tab_bar_edge = "bottom";
      tab_bar_style = "powerline";
      tab_powerline_style = "round";
      active_tab_font_style = "bold";
      inactive_tab_font_style = "normal";
      # Cursor
      cursor_shape = "beam";
      cursor_beam_thickness = "1.5";
      # URLs
      url_style = "curly";
      detect_urls = true;
    };
  };
}
