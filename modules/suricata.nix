# Suricata IDS — passive network intrusion detection on the VPN egress path.
#
# Vantage point: the `protonvpn` WireGuard interface. Because the kill switch
# forces all real egress through the tunnel, this interface carries every
# meaningful outbound flow in *decrypted* form (post-WireGuard), which is the
# correct place to run signature detection — watching the physical NIC would
# only see opaque WireGuard UDP.
#
# Rules: ET Open + the module's default source set, refreshed automatically by
# the bundled `suricata-update` oneshot before the daemon starts. IDS only
# (no inline IPS / NFQUEUE) — alerts to EVE JSON, never drops packets, so it
# cannot wedge connectivity.
#
# If af-packet fails to bind on the WireGuard interface on your kernel, switch
# `interface` to the physical NIC name from `ip -o link` — one-line change.
# Disabled in the gaming-tuned specialisation (see hosts/predator/default.nix).
_:

{
  services.suricata = {
    enable = true;
    # enabledSources / disabledRules keep the module defaults (ET Open et al.).
    settings = {
      # Treat the VPN tunnel address space + RFC1918 as "home"; everything
      # else is external for rule directionality.
      vars.address-groups.HOME_NET = "[10.0.0.0/8,192.168.0.0/16,172.16.0.0/12]";

      # Minimal capture entry — only `interface` is required; suricata's
      # built-in defaults cover cluster-id/cluster-type/threading. Fewer
      # fields = fewer ways for the build-time `suricata -T` to reject it.
      af-packet = [
        { interface = "protonvpn"; }
      ];
    };
  };

  # The tunnel must exist before Suricata tries to open it. Ordered after (and
  # gated on) wg-quick so a VPN-down boot doesn't leave Suricata crash-looping
  # on a missing interface.
  systemd.services.suricata = {
    after = [ "wg-quick-protonvpn.service" ];
    requires = [ "wg-quick-protonvpn.service" ];
  };
}
