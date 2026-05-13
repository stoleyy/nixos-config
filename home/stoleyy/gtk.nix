{ pkgs, colors, ... }:

let
  blackCss = ''
    @define-color window_bg_color ${colors.black};
    @define-color view_bg_color ${colors.black};
    @define-color headerbar_bg_color ${colors.black};
    @define-color popover_bg_color ${colors.black2};
    @define-color sidebar_bg_color ${colors.black};
    window, .background, headerbar, .titlebar, .view, textview text {
      background-color: ${colors.black};
    }
  '';
in
{
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Tela-circle-black-dark";
      package = pkgs.tela-circle-icon-theme.override { colorVariants = [ "black" ]; };
    };
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
      size = 24;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk3.extraCss = blackCss;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraCss = blackCss;
  };

  qt = {
    enable = true;
    platformTheme.name = "kde";
    style.name = "breeze";
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
}
