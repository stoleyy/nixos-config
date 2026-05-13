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

    # Lead with the families Plasma uses (see home/stoleyy/plasma.nix) so GTK
    # fallback / headless rendering / Qt apps without explicit font config all
    # agree with the desktop. Inter + nerd-fonts.geist-mono are installed at
    # the system level via modules/theming.nix.
    fontconfig.defaultFonts = {
      monospace = [ "GeistMono Nerd Font" "JetBrainsMono Nerd Font" "Noto Sans Mono" ];
      sansSerif = [ "Inter" "Noto Sans" "Liberation Sans" ];
      serif     = [ "Noto Serif" "Liberation Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };
}
