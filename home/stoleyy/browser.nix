# Qubes-style browser compartmentalization.
# Each trust domain is a fully isolated Brave instance with its own data dir,
# cookies, history, extensions, and credentials. Color-coded window frames
# make the active domain visible at a glance — like Qubes window borders.
#
# Domains:
#   vault      (GREEN)  — banking, finance, sensitive accounts. Max lockdown.
#   personal   (BLUE)   — daily browsing, YouTube, social media. Standard.
#   untrusted  (RED)    — random links, sketchy sites. LAN-blocked + Tor egress.
#   disposable (ORANGE) — one-shot session, wiped on exit. LAN-blocked + Tor.
#
# Isolated domains (untrusted, disposable) launch via `sg untrusted`, so their
# sockets are owned by the "untrusted" GID (LAN dropped by compartments.nix)
# and they are pointed at the local Tor SOCKS proxy (modules/tor-isolation.nix)
# for Tor-over-VPN egress. stoleyy must be in the `untrusted` group
# (modules/base.nix) or `sg` refuses to switch into it.
{
  pkgs,
  lib,
  theme,
  ...
}:

let
  inherit (theme) hexToRgb colors;

  # ── Trust domain definitions ──
  # isolated = true → runs under "untrusted" GID (LAN blocked via nftables)
  domains = {
    vault = {
      color = "#1B5E20"; # intentional: trust-zone green, not theme color
      frame = "#2E7D32"; # intentional: trust-zone green, not theme color
      label = "Vault";
      description = "Banking, finance, sensitive accounts";
      dataDir = "Brave-Vault";
    };
    personal = {
      color = colors.bg1; # Sanctuary indigo — flows from lib/theme.nix
      frame = colors.bg2;
      label = "Personal";
      description = "Daily browsing, YouTube, social media";
      dataDir = "Brave-Browser"; # default Brave profile
    };
    untrusted = {
      color = "#B71C1C"; # Dark red
      frame = "#C62828";
      label = "Untrusted";
      description = "Random links, unknown sites";
      dataDir = "Brave-Untrusted";
      isolated = true; # LAN blocked
    };
    disposable = {
      color = "#E65100"; # Dark orange
      frame = "#F57C00";
      label = "Disposable";
      description = "One-shot session, wiped on exit";
      dataDir = "Brave-Disposable";
      ephemeral = true;
      isolated = true; # LAN blocked
    };
  };

  # ── Wrapper script generator ──
  mkBraveWrapper =
    name: domain:
    let
      isolated = domain ? isolated && domain.isolated;
      # WebRTC can gather ICE candidates that bypass the SOCKS/VPN egress path
      # and reveal the local LAN or tunnel-internal IP. Isolated (Tor'd) domains
      # force every WebRTC route through the proxy only; the VPN domains keep
      # WebRTC working (video calls) but hide the local LAN address.
      webrtcPolicy = if isolated then "disable_non_proxied_udp" else "default_public_interface_only";
    in
    pkgs.writeShellScriptBin "brave-${name}" ''
      DATA_DIR="''${HOME}/.config/BraveSoftware/${domain.dataDir}"
      ${lib.optionalString (domain ? ephemeral && domain.ephemeral) ''
        # Disposable: wipe previous session, create fresh
        rm -rf "$DATA_DIR"
      ''}
      mkdir -p "$DATA_DIR"
      ${lib.optionalString (domain ? ephemeral && domain.ephemeral) ''
        # Trap: wipe on exit regardless of how browser closes
        trap 'rm -rf "$DATA_DIR"' EXIT INT TERM
      ''}

      # Seed the theme on first run (idempotent — only writes if missing)
      THEME_DIR="$DATA_DIR/Default/Extensions/qubes_theme_${name}"
      if [ ! -d "$THEME_DIR" ]; then
        mkdir -p "$THEME_DIR/1.0"
        cp "${themePath name domain}/manifest.json" "$THEME_DIR/1.0/"
      fi

      # Seed initial preferences — Brave reads this once on first launch
      if [ ! -f "$DATA_DIR/initial_preferences" ]; then
        printf '{"brave":{"sidebar":{"sidebar_show_option":2},"vertical_tabs":{"floating":true}}}\n' > "$DATA_DIR/initial_preferences"
      fi

      ${
        if isolated then
          # Isolated domains: switch to the "untrusted" GID (LAN dropped by
          # modules/compartments.nix) AND route through the local Tor SOCKS
          # proxy (modules/tor-isolation.nix) → Tor-over-VPN egress. Chromium
          # does remote DNS over the socks5 proxy, so no DNS leak.
          ''exec sg untrusted -c "brave --user-data-dir=\"$DATA_DIR\" --class=brave-${name} --proxy-server=socks5://127.0.0.1:9050 --webrtc-ip-handling-policy=${webrtcPolicy} $*"''
        else
          ''exec brave --user-data-dir="$DATA_DIR" --class="brave-${name}" --webrtc-ip-handling-policy=${webrtcPolicy} "$@"''
      }
    '';

  # ── Theme manifest generator (Chromium extension theme) ──
  mkThemeManifest =
    _: domain:
    builtins.toJSON {
      manifest_version = 3;
      version = "1.0";
      name = "Qubes ${domain.label}";
      description = "${domain.label} domain — ${domain.description}";
      theme = {
        colors = {
          frame = hexToRgb domain.frame;
          frame_inactive = hexToRgb domain.color;
          frame_incognito = hexToRgb domain.frame;
          frame_incognito_inactive = hexToRgb domain.color;
          toolbar = hexToRgb domain.color;
          toolbar_text = [
            255
            255
            255
          ];
          tab_text = [
            255
            255
            255
          ];
          tab_background_text = [
            200
            200
            200
          ];
          bookmark_text = [
            255
            255
            255
          ];
          ntp_background = hexToRgb domain.color;
          ntp_text = [
            255
            255
            255
          ];
          omnibox_background = hexToRgb domain.color;
          omnibox_text = [
            255
            255
            255
          ];
        };
      };
    };

  # Write theme manifest to nix store
  themePath = name: domain: pkgs.writeTextDir "manifest.json" (mkThemeManifest name domain);

  # ── Desktop entry generator ──
  mkDesktopEntry = name: domain: {
    name = "Brave (${domain.label})";
    genericName = "Web Browser — ${domain.label} Domain";
    comment = domain.description;
    exec = "brave-${name} %U";
    terminal = false;
    type = "Application";
    icon = "brave-browser";
    categories = [
      "Network"
      "WebBrowser"
    ];
    settings.StartupWMClass = "brave-${name}";
    mimeType = lib.optionals (name == "personal") [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
  };

in
{
  home.packages = lib.mapAttrsToList mkBraveWrapper domains;

  xdg.desktopEntries = (lib.mapAttrs mkDesktopEntry domains) // {
    # Discord — untrusted domain (LAN blocked, VPN internet works)
    discord = {
      name = "Discord";
      genericName = "Chat — Untrusted Domain";
      comment = "Discord (LAN isolated)";
      exec = "discord %U";
      terminal = false;
      type = "Application";
      icon = "discord";
      categories = [
        "Network"
        "InstantMessaging"
      ];
      settings.StartupWMClass = "discord";
    };
  };
}
