# Self-hosted SearXNG — privacy metasearch, localhost-only, behind the system VPN.
#
# Search backend for the Zen `vault`/`personal` zones: no third party ever sees
# your queries — your box makes the aggregated upstream calls, and since the host
# egresses through ProtonVPN, even the upstreams (Brave/DDG/…) see the VPN exit,
# not your real IP. Strictly more private than querying DDG/Brave directly.
#
# Deliberately NOT for the `untrusted`/`disposable` Tor zones: a 127.0.0.1 instance
# can't route through their Tor SOCKS proxy, and pointing them at any endpoint of
# yours would tie Tor traffic to your infra. Those zones use DuckDuckGo/onion.
#
# Wiring it into Zen is a one-time IN-APP step (Settings → Search → add
# `http://127.0.0.1:8888/search?q=%s`, set default) on vault/personal — the engine
# list lives in the binary `search.json.mozlz4`, which is not declaratively
# managed (see home/stoleyy/browser.nix). Localhost-only: no firewall port opened.
{ pkgs, ... }:
let
  port = 8888;
in
{
  # secret_key: generated ONCE into a root-only, non-store file; SearXNG reads it
  # from $SEARXNG_SECRET. Avoids the nix-store exposure an inline `secret_key`
  # would cause (the NixOS wiki warns about exactly this), with no sops round-trip
  # for a key that is purely local and never leaves the box. Its own state dir so
  # it never races the searx module's ownership of /var/lib/searx.
  systemd.services.searx-secret = {
    description = "Generate SearXNG secret_key (once)";
    wantedBy = [ "multi-user.target" ];
    # Order before every plausible searx unit name so the env file exists first
    # (extra names are harmless no-ops if absent).
    before = [
      "searx-init.service"
      "searx.service"
      "uwsgi.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 700 /var/lib/searx-secret
      f=/var/lib/searx-secret/secret.env
      if [ ! -s "$f" ]; then
        umask 077
        printf 'SEARXNG_SECRET=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" > "$f"
      fi
    '';
  };

  services.searx = {
    enable = true;
    package = pkgs.searxng;
    # Standalone runner, NOT uWSGI (this option was named runInUwsgi before the
    # 25.11 rename): environmentFile reliably reaches this process (the uWSGI
    # vassal doesn't inherit it — nixpkgs#292652), and it's ample for a localhost
    # single-user instance.
    configureUwsgi = false;
    environmentFile = "/var/lib/searx-secret/secret.env";
    settings = {
      use_default_settings = true; # merge over SearXNG's defaults (keep all engines)
      general = {
        debug = false;
        instance_name = "predator";
        enable_metrics = false; # no local query stats
        donation_url = false;
        contact_url = false;
      };
      server = {
        bind_address = "127.0.0.1";
        inherit port;
        # secret_key intentionally omitted — supplied via $SEARXNG_SECRET so it
        # never lands in the world-readable nix store.
        limiter = false; # single-user localhost — no self-rate-limiting (no redis needed)
        public_instance = false;
        image_proxy = true; # proxy result thumbnails through searx (no direct hits)
        method = "GET"; # allow GET so the browser's ?q= search URL works
      };
      ui = {
        default_theme = "simple";
        theme_args.simple_style = "dark"; # matches the Sanctuary dark aesthetic
        infinite_scroll = true;
      };
      search = {
        safe_search = 0;
        autocomplete = "duckduckgo"; # completions fetched by YOUR server, not the browser
        default_lang = "en-US";
        formats = [
          "html"
          "json"
        ];
      };
      outgoing = {
        request_timeout = 6.0;
        max_request_timeout = 15.0;
        pool_connections = 100;
        pool_maxsize = 15;
      };
    };
  };
}
