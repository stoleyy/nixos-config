# NetworkManager + nftables firewall, dnscrypt-proxy (adaptive + anonymized DNS), systemd-resolved, ProtonVPN kill-switch support.
_:

let
  # PUBLIC minisign key for the DNSCrypt resolver/relay lists — safe to commit
  # (it only authenticates the downloaded server lists, it is not a secret).
  # Defined once and reused by every `sources.*` block below.
  dnscryptMinisignKey = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
in
{
  networking = {
    networkmanager = {
      enable = true;
      dns = "systemd-resolved"; # explicit hand-off to resolved
    };
    useDHCP = false;
    dhcpcd.enable = false;

    nftables.enable = true;
    # Wazuh manager ports (443, 1515, 55000 TCP + 1514 UDP) are NOT opened
    # here — wazuh-manager.nix is commented out in lib/default.nix. Re-add
    # these when the manager module is enabled:
    #   allowedTCPPorts = [ 443 1515 55000 ];
    #   allowedUDPPorts = [ 1514 ];
    firewall = {
      enable = true;
      # "loose" lets the WireGuard tunnel set up by Proton VPN (via NetworkManager)
      # return traffic through while still validating non-VPN interfaces. "false"
      # would also work but skips all rp_filter checking.
      checkReversePath = "loose";
    };
  };

  # ── DNS architecture ──
  # dnscrypt-proxy (port 5300) → latency-ranked resolver pool via wp2 algorithm.
  # systemd-resolved (port 53) → local cache, DNSSEC validation, forwards to dnscrypt.
  # This gives us adaptive multi-resolver selection (zero custom code) PLUS
  # local caching and DNSSEC, without losing Quad9's threat-blocking.
  services = {
    dnscrypt-proxy = {
      enable = true;
      settings = {
        # wp2 (Weighted Power of Two): picks the better of two random candidates
        # based on real-time RTT + success rates. Zero custom code, adaptive.
        lb_strategy = "wp2";
        lb_estimator = true;

        listen_addresses = [ "127.0.0.1:5300" ];
        max_clients = 250;

        # Use servers that support DNSSEC + no-logging + no-filtering.
        # Quad9 is included in the public resolver list.
        require_dnssec = true;
        require_nolog = true;
        require_nofilter = false; # allow threat-blocking resolvers like Quad9

        # Use encrypted DNS (DoH/DNSCrypt), never plaintext.
        dnscrypt_servers = true;
        doh_servers = true;

        # ── Anonymized DNS / ODoH ──
        # Relay every query through a third party so the resolver never sees
        # this host's source IP. via = ["*"] lets dnscrypt-proxy auto-select
        # relays (zero maintenance, no hard-coded relay names to rot).
        # skip_incompatible = true drops any resolver that cannot be relayed
        # instead of querying it directly — so there is no deanonymizing
        # fallback to a naked DNSCrypt/DoH query. ODoH (oblivious DoH) servers
        # are relay-only by design and layered in alongside.
        odoh_servers = true;
        anonymized_dns = {
          routes = [
            {
              server_name = "*";
              via = [ "*" ];
            }
          ];
          skip_incompatible = true;
        };

        # Source: community-maintained resolver list (default).
        sources.public-resolvers = {
          urls = [
            "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
            "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
          ];
          cache_file = "/var/cache/dnscrypt-proxy/public-resolvers.md";
          minisign_key = dnscryptMinisignKey;
        };

        # Relay list — required for the Anonymized DNS routing configured above.
        sources.relays = {
          urls = [
            "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md"
            "https://download.dnscrypt.info/resolvers-list/v3/relays.md"
          ];
          cache_file = "/var/cache/dnscrypt-proxy/relays.md";
          minisign_key = dnscryptMinisignKey;
        };

        # ODoH (oblivious DoH) server + relay lists.
        sources.odoh-servers = {
          urls = [
            "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-servers.md"
            "https://download.dnscrypt.info/resolvers-list/v3/odoh-servers.md"
          ];
          cache_file = "/var/cache/dnscrypt-proxy/odoh-servers.md";
          minisign_key = dnscryptMinisignKey;
        };
        sources.odoh-relays = {
          urls = [
            "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-relays.md"
            "https://download.dnscrypt.info/resolvers-list/v3/odoh-relays.md"
          ];
          cache_file = "/var/cache/dnscrypt-proxy/odoh-relays.md";
          minisign_key = dnscryptMinisignKey;
        };

        # Local cache — avoids redundant lookups hitting the network.
        cache = true;
        cache_size = 4096;
        cache_min_ttl = 600;
        cache_neg_min_ttl = 60;
      };
    };

    # resolved: local DNS stub, now forwarding to dnscrypt-proxy instead of
    # directly to Quad9. DNSSEC is validated by both dnscrypt-proxy (resolver
    # selection) and resolved (local). DoT disabled here since dnscrypt handles
    # encryption upstream.
    resolved = {
      enable = true;
      dnssec = "true";
      dnsovertls = "false"; # dnscrypt-proxy handles encrypted transport
      llmnr = "false"; # disable LLMNR — credential-theft surface (T1557.001)
      domains = [ "~." ];
      fallbackDns = [
        "9.9.9.9"
        "149.112.112.112"
      ];
      extraConfig = ''
        DNS=127.0.0.1:5300
      '';
    };

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true; # needed for KDE Connect mDNS discovery
    };
  };

}
