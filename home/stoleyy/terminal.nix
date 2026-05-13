{ ... }:

{
  programs.kitty = {
    enable    = true;
    themeFile = "Catppuccin-Mocha";   # F07
    font.name = "JetBrainsMono Nerd Font";
    font.size = 12;
    settings  = {
      enable_audio_bell       = false;
      confirm_os_window_close = 0;
      scrollback_lines        = 10000;
    };
  };
}
