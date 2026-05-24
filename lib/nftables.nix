# Shared nftables helpers for ProtonVPN kill switch management.
#
# mkKillswitchTable allowedIPs
#   Generates a complete `table inet protonvpn_killswitch` block.
#   allowedIPs: list of strings — each becomes an `ip daddr <ip> accept` rule.
#   Strings may be literal IPs (Nix-evaluated) or shell variable references
#   like "$CURRENT_IP" (rendered verbatim; the caller's heredoc expands them).

{ lib }:

{
  mkKillswitchTable =
    allowedIPs:
    let
      endpointRules = lib.concatMapStringsSep "\n      " (ip: "ip daddr ${ip} accept") allowedIPs;
    in
    ''
      table inet protonvpn_killswitch {
        chain output {
          type filter hook output priority -100; policy accept;
          # allow loopback
          oifname "lo" accept
          # allow LAN (printer, OPNsense, Wazuh dashboard, etc.)
          ip daddr 192.168.1.0/24 accept
          # allow link-local + multicast for DHCP/mDNS bootstrap
          ip daddr 169.254.0.0/16 accept
          ip daddr 224.0.0.0/4 accept
          ip daddr 255.255.255.255 accept
          # IPv6: allow link-local + multicast (NDP, mDNS)
          ip6 daddr fe80::/10 accept
          ip6 daddr ff00::/8 accept
          # allow VPN endpoint(s) (so tunnel can establish/reconnect)
          ${endpointRules}
          # allow traffic going through VPN interface
          oifname "protonvpn" accept
          # everything else: drop (kill switch)
          counter drop
        }
      }
    '';
}
