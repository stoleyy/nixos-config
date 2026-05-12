{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (brave.override {
      commandLineArgs = [
        # Wayland / Ozone — render correctly on KDE Plasma 6 Wayland.
        # `UseOzonePlatform` is a no-op on current Chromium; only the hint is needed.
        "--disable-features=WaylandWpColorManagerV1"
        "--ozone-platform-hint=auto"
      ];
    })

    # CLI essentials
    ripgrep
    bat
    fd
    jq
    tree
    htop
    unzip
    p7zip

    # Nix tooling
    nixd
    nixfmt
    nix-output-monitor

    # Media
    vlc
    # F10: easyeffects removed — owned by home-manager services.easyeffects in home/stoleyy.nix
    libreoffice-fresh
  ];

  # Brave debloat via enterprise policy (managed via /etc/brave/policies/managed/).
  # Disables: Rewards, Wallet (crypto), AI Chat (Leo), News, Talk, VPN, Tor mode,
  # default-browser nag, P3A telemetry, and the new-tab "stats" tiles.
  # Sync is left enabled so Windows search engines, bookmarks, and passwords can
  # be brought over with Brave Sync (brave://sync).
  environment.etc."brave/policies/managed/debloat.json".text = builtins.toJSON {
    BraveRewardsDisabled        = true;
    BraveWalletDisabled         = true;
    BraveAIChatEnabled          = false;
    BraveNewsDisabled           = true;
    BraveTalkDisabled           = true;
    BraveVPNDisabled            = true;
    TorDisabled                 = true;
    BraveP3ADisabled            = true;
    DefaultBrowserSettingEnabled = false;
    MetricsReportingEnabled     = false;
    SearchSuggestEnabled        = false;
    SyncDisabled                = false;     # keep on so Windows settings can import
  };

  services.flatpak.enable = true;

  # F17: prefer KDE-native portals on Plasma 6, fall back to GTK only when KDE has no backend
  xdg.portal = {
    enable           = true;
    xdgOpenUsePortal = true;
    config.common.default = [ "kde" "gtk" ];
    extraPortals = with pkgs; [
      kdePackages.xdg-desktop-portal-kde
      xdg-desktop-portal-gtk
    ];
  };
}
