{
  pkgs,
  lib,
  config,
  colors,
  ...
}:

let
  gruvboxCss = ''
    @define-color window_bg_color ${colors.bg0};
    @define-color view_bg_color ${colors.bg0};
    @define-color headerbar_bg_color ${colors.bg0};
    @define-color popover_bg_color ${colors.bg1};
    @define-color sidebar_bg_color ${colors.bg0};
    @define-color accent_bg_color ${colors.yellow};
    @define-color accent_color ${colors.yellow};
    window, .background, headerbar, .titlebar, .view, textview text {
      background-color: ${colors.bg0};
      color: ${colors.fg0};
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
    # cursorTheme intentionally absent — home.pointerCursor (declared in
    # home/stoleyy/hyprland.nix) sets gtk + hyprcursor + XCursor in one place.
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk3.extraCss = gruvboxCss;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraCss = gruvboxCss;
  };

  qt = {
    enable = true;
    platformTheme.name = "kde";
    style.name = "breeze";
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  # KDE's kde-gtk-config (kded6) rewrites these GTK files at runtime so GTK
  # apps follow the Plasma theme. HM's gtk module also owns them, so on the
  # next activation HM finds foreign files, tries to back them up, and
  # collides with its own prior *.backup — the recurring,
  # rebuild-blocking home-manager-stoleyy.service failure (CLAUDE.md
  # Pitfalls). `force` makes HM overwrite them with the declared theme
  # above and never attempt a backup, ending the collision loop. The
  # declarative theme is authoritative; KDE's runtime tweaks to these
  # specific files are intentionally reset on each activation.
  xdg.configFile = {
    "gtk-3.0/settings.ini".force = true;
    "gtk-4.0/settings.ini".force = true;
    "gtk-3.0/gtk.css".force = true;
    "gtk-4.0/gtk.css".force = true;
  };
  # gtk2 rc: HM keys this entry by its absolute path, so force uses the
  # same key (config.home.homeDirectory) to merge rather than create a
  # second conflicting definition for the .gtkrc-2.0 target. HM's gtk2
  # module explicitly sets force = false at normal priority, so mkForce is
  # required to override it.
  home.file."${config.home.homeDirectory}/.gtkrc-2.0".force = lib.mkForce true;
}
