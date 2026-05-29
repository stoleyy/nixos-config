# Tor client + SOCKS proxy for the "untrusted" trust domain (Whonix-style).
#
# This is the egress half of the Qubes-style browser compartments
# (home/stoleyy/browser.nix). The RED "untrusted" and ORANGE "disposable"
# Brave profiles are launched with --proxy-server=socks5://127.0.0.1:9050,
# so their traffic exits through Tor instead of the clearnet path.
#
# Layering, outermost first:
#   Brave (untrusted GID) → Tor SOCKS (127.0.0.1:9050) → Tor circuit
#     → system default route → ProtonVPN tunnel → Tor entry guard
#
# i.e. Tor-over-VPN. The VPN kill switch (modules/protonvpn.nix) still gates
# Tor's own egress, so if the tunnel drops, Tor cannot connect and the
# untrusted browser simply fails to load — fail-closed, no clearnet leak.
#
# Only the browser is torified (per-app SOCKS), not the whole untrusted GID:
# this avoids fighting the VPN kill switch / GID routing with transparent
# nftables NAT, which is fragile to get leak-proof. Non-browser untrusted
# apps continue to egress via the VPN with the LAN blocked (compartments.nix).
_:

{
  services.tor = {
    enable = true;
    # Client-only: opens a local SOCKS listener on 127.0.0.1:9050 (Tor's
    # default — loopback-bound, never reachable from the LAN). No relay,
    # no exit, no onion services; this node never carries others' traffic.
    client.enable = true;
  };
}
