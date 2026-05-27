# Qubes-style browser compartmentalization.
# Each trust domain is a fully isolated Brave instance with its own data dir,
# cookies, history, extensions, and credentials. Color-coded window frames
# make the active domain visible at a glance — like Qubes window borders.
#
# Domains:
#   vault      (GREEN)  — banking, finance, sensitive accounts. Max lockdown.
#   personal   (BLUE)   — daily browsing, YouTube, social media. Standard.
#   untrusted  (RED)    — random links, sketchy sites. Aggressive isolation.
#   disposable (ORANGE) — one-shot sessions, wiped on exit. Click unknown links.
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

      ${
        if domain ? isolated && domain.isolated then
          ''exec sg untrusted -c "brave --user-data-dir=\"$DATA_DIR\" --class=brave-${name} $*"''
        else
          ''exec brave --user-data-dir="$DATA_DIR" --class="brave-${name}" "$@"''
      }
    '';

  # ── Theme manifest generator (Chromium extension theme) ──
  mkThemeManifest =
    name: domain:
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
