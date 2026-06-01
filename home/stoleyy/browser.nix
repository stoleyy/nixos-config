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
    // 3rd-party cookie isolation for every zone via dFPI / Total Cookie
    // Protection — the modern replacement for the obsolete FPI that arkenfox
    // itself disables. Firefox default is already 5; set explicitly so cookie
    // isolation never silently depends on the ETP category.
    user_pref("network.cookie.cookieBehavior", 5);
    // WebRTC fully off — no STUN/ICE IP leak on any domain (video calls unused)
    user_pref("media.peerconnection.enabled", false);
    // No in-browser DoH — the OS resolver (dnscrypt-proxy, anonymized) is authoritative
    user_pref("network.trr.mode", 5);
    // NVIDIA VAAPI HW video decode — ATTEMPT only. Firefox blocklists hardware
    // decode on NVIDIA + Wayland (FEATURE_HARDWARE_VIDEO_DECODING_NO_LINUX_NVIDIA),
    // so this is likely a no-op on the Hyprland / Plasma-Wayland sessions; verify
    // at about:support ("Media" → HW decoding). The RDD sandbox is left ON (the
    // wrapper no longer exports MOZ_DISABLE_RDD_SANDBOX) — modern Firefox runs
    // VAAPI inside it. If decode never engages, drop these; mpv/Jellyfin do NVDEC.
    user_pref("media.ffmpeg.vaapi.enabled", true);
    user_pref("media.hardware-video-decoding.force-enabled", true);

    /* Performance — safe on this hardware (64 GB RAM); not touched by arkenfox. */
    user_pref("browser.cache.memory.capacity", 131072);
    user_pref("network.http.max-connections", 1800);
    user_pref("network.http.max-persistent-connections-per-server", 10);
  '';

  vaultOverrides = ''

    /* ===== vault — banking/finance ===== */
    // Persist logins/cookies across sessions (relax arkenfox's clear-on-shutdown
    // so "remember this device" / 2FA survives). HTTPS-Only is already on
    // globally via arkenfox (dom.security.https_only_mode), so it is not repeated.
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
    // Tor-Browser-grade anti-fingerprinting. arkenfox leaves RFP OFF (favouring
    // the lighter FPP for daily use); turn it ON here — RFP is what actually
    // activates letterboxing and spoofs UA/timezone/screen for uniformity.
    // FPI is deliberately NOT used (obsolete; arkenfox disables it) — cookie
    // isolation comes from dFPI (commonOverrides: cookieBehavior=5).
    user_pref("privacy.resistFingerprinting", true);
    user_pref("privacy.resistFingerprinting.letterboxing", true);
    user_pref("privacy.spoof_english", 2);
    // Kill WebGL on the hostile zones — a large fingerprint + exploit surface
    // that random-link / throwaway browsing does not need.
    user_pref("webgl.disabled", true);
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

  # Quality-of-life prefs for every domain. arkenfox-safe — no privacy/telemetry
  # impact, and none of these keys are set by arkenfox or the overrides above.
  utilityOverrides = ''

    /* ===== Quality-of-life (arkenfox-safe) ===== */
    // Ctrl+Tab cycles most-recently-used tabs, not left-to-right
    user_pref("browser.ctrlTab.sortByRecentlyUsed", true);
    // Find: highlight every match + show scrollbar position markers
    user_pref("findbar.highlightAll", true);
    // Don't destroy the window when the last tab is closed
    user_pref("browser.tabs.closeWindowWithLastTab", false);
  '';

  # arkenfox base → common → per-domain → utility (later wins).
  mkUserJs =
    name:
    pkgs.writeText "zen-${name}-user.js" (
      arkenfoxBase
      + "\n"
      + commonOverrides
      + "\n"
      + (domainOverrides.${name} or "")
      + "\n"
      + utilityOverrides
    );

  # Per-domain chrome styling. Trusted zones (vault/personal) get a frosted
  # "Sanctuary glass" toolbar/sidebar; hostile zones stay solid + plain (RFP
  # letterboxing standardizes their geometry, so glass is pointless there).
  #
  # CHROME-ONLY frost: no window/content transparency prefs are set and the
  # Hyprland rule keeps the window opaque, so web content — video included
  # (e.g. YouTube) — is always fully opaque. The blur is of the page behind the
  # toolbar, never the desktop. Primary trust signal stays the Hyprland border;
  # Zen chrome selectors may shift between releases — verify/adjust on-box.
  mkUserChrome =
    _name: domain:
    let
      glass = !(domain.isolated or false);
    in
    pkgs.writeText "userChrome.css" ''
      /* ===== Sanctuary chrome — ${domain.label} ===== */
      :root {
        --sanctuary-trust: ${domain.color};
        --sanctuary-accent: ${domain.frame};
      }
      ${
        if glass then
          ''
            /* Frosted Sanctuary glass — chrome only, content stays opaque.
               ${domain.color}cc is ~80% tint over the page; lower the alpha
               on-box for more show-through. */
            #navigator-toolbox,
            #nav-bar,
            #zen-appcontent-navbar-container,
            #zen-sidebar-web-panel-wrapper,
            #sidebar-box {
              background-color: ${domain.color}cc !important;
              backdrop-filter: blur(14px) saturate(1.25) !important;
            }
          ''
        else
          ''
            /* Hostile zones: solid + plain (no glass under RFP letterboxing). */
            #navigator-toolbox,
            #nav-bar,
            #zen-appcontent-navbar-container {
              background-color: ${domain.color} !important;
            }
          ''
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

      # Wayland app_id (per-domain window border). We intentionally do NOT set
      # MOZ_DISABLE_RDD_SANDBOX — VAAPI runs inside the RDD sandbox on modern
      # Firefox, and disabling it traded a sandbox away for HW decode that
      # NVIDIA + Wayland blocklists anyway.
      export MOZ_ENABLE_WAYLAND=1

      ${
        let
          launch =
            if isolated then
              # Switch to the "untrusted" GID (LAN dropped by modules/compartments.nix).
              # Tor egress is in this profile's user.js. $* mirrors the prior Brave
              # wrapper — sufficient for URL args from xdg-open / the launcher.
              ''sg untrusted -c "zen-beta --profile \"$DATA_DIR\" --name zen-${name} --class zen-${name} $*"''
            else
              ''zen-beta --profile "$DATA_DIR" --name zen-${name} --class zen-${name} "$@"'';
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
