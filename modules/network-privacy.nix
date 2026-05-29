# Automated network-identity obfuscation — randomized MAC, suppressed DHCP
# hostname, and RFC 4941 temporary IPv6 addresses. Layers on top of the
# ProtonVPN tunnel (modules/protonvpn.nix) and anonymized DNS (networking.nix).
#
# Goal: a passive observer on the local link (coffee-shop AP, ISP CPE, a
# compromised LAN peer) learns as little stable, device-identifying metadata
# as possible — no fixed hardware MAC, no "predator" hostname leaked via DHCP,
# no long-lived IPv6 interface identifier.
_:

{
  networking.networkmanager = {
    # Re-randomize the L2 MAC on every Wi-Fi connection activation. "random"
    # (not "stable") means even the cloned MAC rotates, so the address seen on
    # the wire is never the burned-in hardware MAC and never repeats across
    # sessions. This is the real privacy use case — roaming onto untrusted APs.
    wifi.macAddress = "random";
    # Wired link: keep the stable hardware MAC. This desktop sits behind the
    # user's own OPNsense router; randomizing the ethernet MAC on every
    # activation broke connectivity (gen 18 ok → gen 19 dead: the wired link
    # got no usable DHCP lease/route, so wg-quick-protonvpn could never reach
    # the Proton endpoint, the tunnel stayed down, and the fail-closed
    # killswitch then blocked everything). MAC randomization buys ~nothing on
    # one's own LAN, so preserve the permanent MAC here.
    ethernet.macAddress = "preserve";
  };

  # Connection/device defaults that NetworkManager has no first-class NixOS
  # option for. conf.d is read after NetworkManager.conf, so these are the
  # effective defaults for every connection profile.
  environment.etc."NetworkManager/conf.d/00-privacy.conf".text = ''
    [connection]
    # Don't broadcast the hostname ("predator") in DHCP requests — a captive
    # portal or DHCP server otherwise logs a stable, identifying name.
    ipv4.dhcp-send-hostname=false
    ipv6.dhcp-send-hostname=false
    # RFC 4941 temporary IPv6 addresses: prefer a rotating address for
    # outbound connections instead of a stable EUI-64 derived from the MAC.
    ipv6.ip6-privacy=2

    [device]
    # Randomize the MAC used during Wi-Fi scans too (NM default is "yes";
    # pinned so a future change can't silently expose the hardware MAC while
    # probing for networks).
    wifi.scan-rand-mac-address=yes
  '';
}
