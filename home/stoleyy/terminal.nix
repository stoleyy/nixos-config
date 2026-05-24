_:

{
  programs.kitty = {
    enable = true;
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
      # Deltarune Sanctuary palette
      background = "#000000";
      foreground = "#C8CAE0";
      selection_background = "#0A094E";
      selection_foreground = "#C8CAE0";
      cursor = "#5987C6";
      color0 = "#000000";
      color1 = "#9B3C3C";
      color2 = "#3C4B9B";
      color3 = "#5987C6";
      color4 = "#324DA7";
      color5 = "#3C4B9B";
      color6 = "#5987C6";
      color7 = "#B2B5CF";
      color8 = "#5D5E69";
      color9 = "#B06060";
      color10 = "#5987C6";
      color11 = "#8D8FA7";
      color12 = "#B2B5CF";
      color13 = "#8D8FA7";
      color14 = "#5987C6";
      color15 = "#C8CAE0";
      active_tab_background = "#0A094E";
      active_tab_foreground = "#C8CAE0";
      inactive_tab_background = "#07062F";
      inactive_tab_foreground = "#8D8FA7";
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
      url_color = "#5987C6";
      detect_urls = true;
    };
  };
}
