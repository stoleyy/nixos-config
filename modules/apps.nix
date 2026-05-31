# User-facing applications: CLI tools, ProtonVPN GUI.
# The web browser (Zen + four Qubes-style trust domains) is declared in
# home/stoleyy/browser.nix via the programs.zen-browser home-manager module.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # CLI essentials
    ripgrep
    fd
    jq
    tree
    htop
    unzip
    p7zip
    # update-desktop-database — clears openhuman's non-fatal
    # "Failed to run OS command 'update-desktop-database'" + the
    # "[deep-link] register_all failed" warning (deep-link registration
    # shells out to it).
    desktop-file-utils
    # Git toolchain — lazygit TUI for staging/squashing, gh for repo ops,
    # delta as the pretty pager (wired in home/stoleyy/git.nix).
    lazygit
    gh
    delta

    # Media
    # libreoffice: run on-demand via `nix run nixpkgs#libreoffice-fresh` (2.6 GiB savings)

    # VPN
    vopono # ephemeral per-app VPN namespaces: `vopono exec --provider custom firefox`

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

  # Flatpak disabled — all apps are declaratively managed via Nix.
  # Prevents accidental re-installs of duplicate Steam/qBittorrent/etc.
  services.flatpak.enable = false;

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
