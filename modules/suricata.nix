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
    # Disable ICS/OT protocol rules that fail to parse because modbus + dnp3
    # app-layer detection is not compiled into the nixpkgs suricata build.
    # Extends the module's default (dnp3 2270000-2270004) with the remaining
    # failing dnp3 sids and all modbus sids.
    disabledRules = [
      # dnp3 — module default (2270000-2270004) + 2270005-2270006
      "2270000"
      "2270001"
      "2270002"
      "2270003"
      "2270004"
      "2270005"
      "2270006"
      # modbus — all sids in suricata.rules
      "2250001"
      "2250002"
      "2250003"
      "2250004"
      "2250005"
      "2250006"
      "2250007"
      "2250008"
      "2250009"
    ];
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

      # EVE JSON: structured alert log consumed by vector.
      # alert + anomaly types only — no flow/dns/http bulk logging.
      outputs = [
        {
          "eve-log" = {
            enabled = true;
            filetype = "regular";
            filename = "eve.json";
            "community-id" = true;
            types = [
              {
                alert = {
                  metadata = true;
                };
              }
              { anomaly = { }; }
            ];
          };
        }
      ];
    };
  };

  # The tunnel must exist before Suricata tries to open it. Ordered after (and
  # gated on) wg-quick so a VPN-down boot doesn't leave Suricata crash-looping
  # on a missing interface.
  systemd.services.suricata = {
    after = [ "wg-quick-protonvpn.service" ];
    requires = [ "wg-quick-protonvpn.service" ];
    serviceConfig = {
      # systemd creates /var/log/suricata owned by the service before start,
      # fixing the "Permission denied" eve.json write failure.
      # 0755 (not the default 0700) so vector (non-root) can tail eve.json.
      LogsDirectory = "suricata";
      LogsDirectoryMode = "0755";
    };
  };
}
