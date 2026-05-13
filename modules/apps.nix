{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (brave.override {
      commandLineArgs = [
        # Wayland / Ozone — render correctly on KDE Plasma 6 / Hyprland Wayland.
        "--ozone-platform-hint=auto"
        # VAAPI on NVIDIA — Chromium hard-blocklists VAAPI for NVIDIA GPUs by
        # default. These flags bypass the blocklist; combined with
        # nvidia-vaapi-driver (in modules/nvidia.nix extraPackages) and
        # LIBVA_DRIVER_NAME=nvidia (sessionVariable), YouTube 4K decodes on
        # NVDEC at single-digit CPU usage instead of 30-40%.
        # WaylandWpColorManagerV1 + UseMultiPlaneFormatForHardwareVideo enable
        # HDR pass-through on Plasma 6.4+. If page chrome washes out under HDR,
        # remove those two features and re-add `--disable-features=WaylandWpColorManagerV1`.
        "--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiVideoDecodeLinuxGL,VaapiOnNvidiaGPUs,WaylandWpColorManagerV1,UseMultiPlaneFormatForHardwareVideo"
        # Vulkan ANGLE renderer — better Wayland/NVIDIA performance than the
        # default GL backend.
        "--use-gl=angle"
        "--use-angle=vulkan"
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
    # Git toolchain — lazygit TUI for staging/squashing, gh for repo ops,
    # delta as the pretty pager (wired in home/stoleyy/git.nix).
    lazygit
    gh
    delta

    # Nix tooling
    nixd
    nixfmt
    nix-output-monitor

    # Media
    vlc
    # F10: easyeffects removed — owned by home-manager services.easyeffects in home/stoleyy.nix
    libreoffice-fresh

    # VPN
    # Proton's official GTK client. Drives kernel WireGuard through
    # NetworkManager (proton-vpn-network-manager is bundled), so the data
    # path is the in-kernel `wireguard` module — same as wg-quick — with the
    # UI on top. Account credentials are kept in the SecretService keyring
    # (KWallet under Plasma; install gnome-keyring if you ever want this to
    # work cleanly under the Hyprland session).
    # Launcher: "Proton VPN" desktop entry, binary `protonvpn-app`.
    # `stoleyy` is already in the `networkmanager` group (modules/base.nix),
    # so polkit doesn't prompt for a password on connect.
    protonvpn-gui
  ];

  # Brave debloat via enterprise policy (managed via /etc/brave/policies/managed/).
  # Disables: Rewards, Wallet (crypto), AI Chat (Leo), News, Talk, VPN, Tor mode,
  # default-browser nag, P3A telemetry, and the new-tab "stats" tiles.
  # Sync is left enabled so Windows search engines, bookmarks, and passwords can
  # be brought over with Brave Sync (brave://sync).
  environment.etc."brave/policies/managed/debloat.json".text = builtins.toJSON {
    BraveRewardsDisabled = true;
    BraveWalletDisabled = true;
    BraveAIChatEnabled = false;
    BraveNewsDisabled = true;
    BraveTalkDisabled = true;
    BraveVPNDisabled = true;
    TorDisabled = true;
    BraveP3ADisabled = true;
    DefaultBrowserSettingEnabled = false;
    MetricsReportingEnabled = false;
    SearchSuggestEnabled = false;
    SyncDisabled = false; # keep on so Windows settings can import
  };

  services.flatpak.enable = true;

  # F17: prefer KDE-native portals on Plasma 6, fall back to GTK only when KDE has no backend.
  # modules/hyprland.nix extends extraPortals with xdg-desktop-portal-hyprland for the
  # Hyprland session; the hyprland session config in this attrset is also extended there.
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config.common.default = [
      "kde"
      "gtk"
    ];
    extraPortals = with pkgs; [
      kdePackages.xdg-desktop-portal-kde
      xdg-desktop-portal-gtk
    ];
  };
}
