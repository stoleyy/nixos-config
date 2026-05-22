{ pkgs, lib, ... }:

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

  # DNS goes to the OPNsense laptop running Unbound at 192.168.1.114.
  # OPNsense and predator are peer hosts on the home-router LAN (the
  # OPNsense laptop only has one ethernet port — it's not an inline
  # gateway). As of 2026-05-14 the OPNsense single NIC (ue0) is assigned
  # to the LAN role at 192.168.1.114/24; predator reaches it as a normal
  # LAN peer. OPNsense-side requirements:
  #   - 192.168.1.114 stable (static IP outside the home router's DHCP pool)
  #   - Unbound listens on LAN (Services → Unbound DNS → Network Interfaces)
  #   - default OPNsense LAN firewall is "allow all from LAN" so no extra rule needed
  #
  # OPNsense is listed first in DNS= so it gets all queries when reachable
  # (Wazuh visibility) — systemd-resolved sticks to the first reachable
  # server. Quad9 follows in the *same* DNS= list (not only fallbackDns):
  # when ProtonVPN routes 0.0.0.0/0 through the WG tunnel, OPNsense
  # (LAN-only) becomes unreachable and resolved fails over to Quad9 within
  # the DNS= rotation after the first timeout, instead of stalling for
  # seconds on the sole server before reaching FallbackDns (the classic
  # "internet looks broken the moment the VPN connects" symptom).
  #
  # DNS goes straight to Quad9 over TLS (port 853), bypassing OPNsense
  # Unbound. Quad9 provides DNSSEC validation + threat-domain blocking.
  # strict DoT = queries never fall back to plaintext.
  services = {
    resolved = {
      enable = true;
      dnssec = "true";
      dnsovertls = "true";
      llmnr = "false"; # disable LLMNR — credential-theft surface (T1557.001)
      domains = [ "~." ];
      fallbackDns = [
        "149.112.112.112#dns.quad9.net"
        "2620:fe::9#dns.quad9.net"
      ];
      extraConfig = ''
        DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net
      '';
    };

    printing = {
      enable = true;
      drivers = with pkgs; [
        gutenprint
        gutenprintBin
        hplip
      ];
      browsing = false; # F-22: cupsd Browsing directive off
      listenAddresses = [ "localhost:631" ]; # F-22: bind only to loopback
    };

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true; # needed for KDE Connect mDNS discovery
    };
  };

  # F-22: disable cups-browsed separately — `browsing = false` only controls cupsd;
  # cups-browsed is a separate unit (CVE-2024-47175 chain).
  systemd.services.cups-browsed.enable = lib.mkForce false;
}
