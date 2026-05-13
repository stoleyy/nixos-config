{ pkgs, ... }:

{
  gtk = {
    enable = true;
    theme = {
      name    = "Colloid-Green-Dark";
      package = pkgs.colloid-gtk-theme.override {
        themeVariants = [ "green" ];
        colorVariants = [ "dark" ];
        tweaks        = [ "gruvbox" "rimless" ];
      };
    };
    iconTheme = {
      name    = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name    = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
      size    = 24;
    };
    font = {
      name = "Noto Sans";
      size = 10;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    name       = "Bibata-Modern-Ice";
    package    = pkgs.bibata-cursors;
    size       = 24;
  };

  # `programs.dconf.enable = true` is set system-wide in modules/base.nix.
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
}
