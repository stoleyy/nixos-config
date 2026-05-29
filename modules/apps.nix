# User-facing applications: Brave, Zen Browser, CLI tools, ProtonVPN GUI.
{ pkgs, inputs, ... }:

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

    # Zen Browser — privacy-focused Firefox fork with vertical tabs.
    # Sourced from the zen-browser/desktop community flake (pre-built binaries).
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Brave debloat + privacy hardening via enterprise policy (managed via
  # /etc/brave/policies/managed/). Applies browser-wide, to all four trust
  # domains. Disables: Rewards, Wallet (crypto), AI Chat (Leo), News, Talk,
  # VPN, Tor mode, default-browser nag, P3A telemetry, and the new-tab "stats"
  # tiles — and hardens WebRTC IP handling (see WebRtcIPHandling below).
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
    SyncDisabled = false; # deliberately enabled — user's cross-device sync (see note above)

    # ── WebRTC IP-leak hardening (fingerprint / deanonymization) ──
    # WebRTC can reveal your LOCAL (LAN) IP and bypass the VPN via STUN — a
    # tracking + deanonymization vector that Brave's farbling does NOT cover.
    # "disable_non_proxied_udp" is the leak-proof setting: it blocks ALL
    # non-proxied WebRTC UDP, so no STUN probe can expose the local, VPN, or
    # real IP on ANY profile — including the Tor-routed untrusted/disposable
    # zones, where it also stops WebRTC from punching around the Tor circuit.
    # Trade-off: in-browser WebRTC voice/video calls won't work — that is the
    # intended sacrifice here (video calls are not used).
    #
    # Fingerprint randomization ("farbling") is left at Brave's default
    # Standard level: upstream sunset the old "Strict" mode in 1.64, so
    # Standard is the strongest in-Brave protection and nothing here disables
    # it. True fingerprint *uniformity* would require Mullvad/Tor Browser —
    # deliberately not used here (normalized on Brave for one consistent
    # compartment model + sync).
    WebRtcIPHandling = "disable_non_proxied_udp";
  };

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
