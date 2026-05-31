# Qubes-style browser compartmentalization — Zen (Firefox fork), arkenfox-hardened.
# Each trust domain is a fully isolated Zen instance with its own profile dir
# (~/.zen/<domain>), cookies, history, extensions, and credentials. Color-coded
# window borders (Hyprland) make the active domain visible at a glance — like
# Qubes window frames.
#
# Domains:
#   vault      (GREEN)  — banking, finance, sensitive accounts. HTTPS-only.
#   personal   (BLUE)   — daily browsing, YouTube, social media. Standard.
#   untrusted  (RED)    — random links, sketchy sites. LAN-blocked + Tor egress.
#   disposable (ORANGE) — one-shot session, wiped on exit. LAN-blocked + Tor.
#
# Hardening: every profile starts from the pinned arkenfox user.js (inputs.arkenfox)
# and layers common + per-domain overrides. Browser-wide enterprise policy
# (programs.zen-browser.policies) force-installs uBlock Origin + the KeePassXC
# connector, blocks all other extensions, and locks telemetry/DoH/Pocket off.
#
# Isolated domains (untrusted, disposable) launch via `sg untrusted`, so their
# sockets are owned by the "untrusted" GID (LAN dropped by compartments.nix);
# Tor egress is baked into those profiles' user.js (SOCKS 127.0.0.1:9050, remote
# DNS) → Tor-over-VPN. stoleyy must be in the `untrusted` group (modules/base.nix)
# or `sg` refuses to switch into it. Firefox does its networking in the parent
# process, which inherits the untrusted egid, so the nftables skgid LAN-drop
# catches all browser traffic; the loopback SOCKS hop is not in the dropped
# RFC-1918/ULA ranges, so Tor egress is unaffected.
{
  pkgs,
  lib,
  theme,
  inputs,
  ...
}:

let
  inherit (theme) colors;

  # ── Trust domain definitions ──
  # isolated = true → runs under the "untrusted" GID (LAN blocked via nftables)
  #                   and routes through Tor (proxy prefs in its user.js).
  # ephemeral = true → profile dir wiped on every launch and exit.
  domains = {
    vault = {
      color = "#1B5E20"; # intentional: trust-zone green, not theme color
      frame = "#2E7D32";
      label = "Vault";
      description = "Banking, finance, sensitive accounts";
    };
    personal = {
      color = colors.bg1; # Sanctuary indigo — flows from lib/theme.nix
      frame = colors.bg2;
      label = "Personal";
      description = "Daily browsing, YouTube, social media";
    };
    untrusted = {
      color = "#B71C1C"; # Dark red
      frame = "#C62828";
      label = "Untrusted";
      description = "Random links, unknown sites";
      isolated = true;
    };
    disposable = {
      color = "#E65100"; # Dark orange
      frame = "#F57C00";
      label = "Disposable";
      description = "One-shot session, wiped on exit";
      isolated = true;
      ephemeral = true;
    };
  };

  # ── arkenfox base + Sanctuary overrides ──
  arkenfoxBase = builtins.readFile (inputs.arkenfox + "/user.js");

  commonOverrides = ''

    /* ===== Sanctuary common overrides (all trust domains) ===== */
    // Enable per-domain userChrome.css (trust-zone coloring)
    user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
    // NVIDIA VAAPI hardware video decode (nvidia-vaapi-driver + LIBVA_DRIVER_NAME=nvidia, modules/nvidia.nix)
    user_pref("media.ffmpeg.vaapi.enabled", true);
    user_pref("media.hardware-video-decoding.force-enabled", true);
    user_pref("media.rdd-ffmpeg.enabled", true);
    // WebRTC fully off — no STUN/ICE IP leak on any domain (video calls unused)
    user_pref("media.peerconnection.enabled", false);
    // No in-browser DoH — the OS resolver (dnscrypt-proxy, anonymized) is authoritative
    user_pref("network.trr.mode", 5);
  '';

  vaultOverrides = ''

    /* ===== vault — banking/finance ===== */
    user_pref("dom.security.https_only_mode", true);
    // Persist logins/cookies across sessions (don't sanitize on shutdown)
    user_pref("privacy.sanitize.sanitizeOnShutdown", false);
  '';

  personalOverrides = ''

    /* ===== personal — daily driver ===== */
    user_pref("privacy.sanitize.sanitizeOnShutdown", false);
  '';

  # untrusted + disposable share this aggressive, Tor-routed profile.
  isolatedOverrides = ''

    /* ===== untrusted / disposable — Tor egress + max hardening ===== */
    // Tor SOCKS (modules/tor-isolation.nix); DNS resolved over Tor (no leak)
    user_pref("network.proxy.type", 1);
    user_pref("network.proxy.socks", "127.0.0.1");
    user_pref("network.proxy.socks_port", 9050);
    user_pref("network.proxy.socks_version", 5);
    user_pref("network.proxy.socks_remote_dns", true);
    user_pref("network.proxy.allow_hijacking_localhost", true);
    // First-party isolation + letterboxing (Tor-Browser-grade anti-fingerprinting)
    user_pref("privacy.firstparty.isolate", true);
    user_pref("privacy.resistFingerprinting.letterboxing", true);
    // JIT off — shrink the JS-engine exploit surface (breaks some sites/WASM; toggle if needed)
    user_pref("javascript.options.ion", false);
    user_pref("javascript.options.baselinejit", false);
    user_pref("javascript.options.wasm", false);
    // Clear everything on shutdown
    user_pref("privacy.sanitize.sanitizeOnShutdown", true);
  '';

  domainOverrides = {
    vault = vaultOverrides;
    personal = personalOverrides;
    untrusted = isolatedOverrides;
    disposable = isolatedOverrides;
  };

  # arkenfox base → common overrides → per-domain overrides (later wins).
  mkUserJs =
    name:
    pkgs.writeText "zen-${name}-user.js" (
      arkenfoxBase + "\n" + commonOverrides + "\n" + (domainOverrides.${name} or "")
    );

  # Per-domain chrome tint. Primary trust signal stays the Hyprland window
  # border; this is a best-effort secondary cue (Zen chrome selectors may shift
  # between releases — verify and adjust if a release moves the toolbox id).
  mkUserChrome =
    _name: domain:
    pkgs.writeText "userChrome.css" ''
      /* Sanctuary trust-domain tint — ${domain.label} */
      :root {
        --sanctuary-trust: ${domain.color};
        --sanctuary-accent: ${domain.frame};
      }
      #navigator-toolbox,
      #nav-bar,
      .browser-toolbar,
      #zen-appcontent-navbar-container {
        background-color: ${domain.color} !important;
      }
      #nav-bar {
        box-shadow: inset 0 -2px 0 0 ${domain.frame} !important;
      }
    '';

  # ── Wrapper script generator ──
  mkZenWrapper =
    name: domain:
    let
      ephemeral = domain.ephemeral or false;
      isolated = domain.isolated or false;
    in
    pkgs.writeShellScriptBin "zen-${name}" ''
      DATA_DIR="''${HOME}/.zen/${name}"
      ${lib.optionalString ephemeral ''
        # Disposable: wipe previous session, recreate fresh; wipe again on exit.
        rm -rf "$DATA_DIR"
        trap 'rm -rf "$DATA_DIR"' EXIT INT TERM
      ''}
      mkdir -p "$DATA_DIR/chrome"

      # Seed arkenfox user.js + trust-zone userChrome (authoritative every launch).
      install -m644 ${mkUserJs name} "$DATA_DIR/user.js"
      install -m644 ${mkUserChrome name domain} "$DATA_DIR/chrome/userChrome.css"

      # Wayland app_id (per-domain window border) + NVIDIA VAAPI in the RDD process.
      export MOZ_ENABLE_WAYLAND=1
      export MOZ_DISABLE_RDD_SANDBOX=1

      ${
        let
          launch =
            if isolated then
              # Switch to the "untrusted" GID (LAN dropped by modules/compartments.nix).
              # Tor egress is in this profile's user.js. $* mirrors the prior Brave
              # wrapper — sufficient for URL args from xdg-open / the launcher.
              ''sg untrusted -c "zen --profile \"$DATA_DIR\" --name zen-${name} --class zen-${name} $*"''
            else
              ''zen --profile "$DATA_DIR" --name zen-${name} --class zen-${name} "$@"'';
        in
        # Ephemeral domains must NOT exec — the wrapper shell has to outlive the
        # browser so its EXIT/INT/TERM trap wipes the profile on close. Others exec.
        if ephemeral then launch else "exec ${launch}"
      }
    '';

  # ── Desktop entry generator ──
  mkDesktopEntry = name: domain: {
    name = "Zen (${domain.label})";
    genericName = "Web Browser — ${domain.label} Domain";
    comment = domain.description;
    exec = "zen-${name} %U";
    terminal = false;
    type = "Application";
    icon = "zen-browser";
    categories = [
      "Network"
      "WebBrowser"
    ];
    settings.StartupWMClass = "zen-${name}";
    mimeType = lib.optionals (name == "personal") [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
  };

in
{
  # Browser-wide enterprise policy (wrapped into Zen's distribution/policies.json
  # by the module). Applies to all four profiles. The Gecko equivalent of the old
  # Brave debloat policy, hardened: extension allowlist, telemetry/DoH/Pocket off.
  programs.zen-browser = {
    enable = true;
    # KeePassXC-Browser native messaging bridge (KeePassXC itself is firejailed
    # --net=none in modules/compartments.nix; the proxy talks over a unix socket).
    nativeMessagingHosts = [ pkgs.keepassxc ];
    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisableFirefoxAccounts = true; # no Mozilla account / Sync (cross-device beacon)
      DisablePocket = true;
      DisableFormHistory = true;
      NoDefaultBookmarks = true;
      OfferToSaveLogins = false; # KeePassXC is authoritative
      PasswordManagerEnabled = false;
      SearchSuggestEnabled = false;
      NetworkPrediction = false;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      # Don't self-DoH: keep DNS on the OS stub (systemd-resolved → dnscrypt-proxy,
      # already encrypted + anonymized). Matches the old Brave DnsOverHttpsMode=off.
      DNSOverHTTPS = {
        Enabled = false;
        Locked = true;
      };
      FirefoxHome = {
        Search = true;
        TopSites = false;
        SponsoredTopSites = false;
        Highlights = false;
        Pocket = false;
        SponsoredPocket = false;
        Snippets = false;
      };
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        UrlbarInterventions = false;
        SkipOnboarding = true;
        MoreFromMozilla = false;
      };
      # Aggressive: block every extension except the allowlisted force-installs.
      ExtensionSettings = {
        "*" = {
          installation_mode = "blocked";
          blocked_install_message = "Extensions are locked by NixOS policy (home/stoleyy/browser.nix).";
        };
        "uBlock0@raymondhill.net" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        };
        "keepassxc-browser@keepassxc.org" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi";
        };
      };
    };
  };

  # zen-vault / zen-personal / zen-untrusted / zen-disposable launchers.
  home.packages = lib.mapAttrsToList mkZenWrapper domains;

  xdg.desktopEntries =
    (lib.mapAttrs' (name: domain: lib.nameValuePair "zen-${name}" (mkDesktopEntry name domain)) domains)
    // {
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

  # Deterministic default browser → the personal domain (not Zen's bare profile).
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "zen-personal.desktop";
      "x-scheme-handler/http" = "zen-personal.desktop";
      "x-scheme-handler/https" = "zen-personal.desktop";
      "application/xhtml+xml" = "zen-personal.desktop";
    };
  };
}
