{ pkgs, ... }:

{
  fonts = {
    enableDefaultPackages = true;
    fontDir.enable        = true;

    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
      jetbrains-mono
      fira-code
      fira-code-symbols          # F08: ligature symbols for fira-code
      nerd-fonts.jetbrains-mono
    ];

    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" "Noto Sans Mono" ];
      sansSerif = [ "Noto Sans" "Liberation Sans" ];
      serif     = [ "Noto Serif" "Liberation Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };
}
