{ pkgs, lib, ... }:

{
  networking.networkmanager = {
    enable = true;
    dns    = "systemd-resolved";   # explicit hand-off to resolved
  };
  networking.useDHCP       = false;
  networking.dhcpcd.enable = false;

  networking.firewall.enable          = true;
  networking.nftables.enable          = true;
  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ ];
  # "loose" lets the WireGuard tunnel set up by Proton VPN (via NetworkManager)
  # return traffic through while still validating non-VPN interfaces. "false"
  # would also work but skips all rp_filter checking.
  networking.firewall.checkReversePath = "loose";

  # DNS goes to the OPNsense laptop running Unbound at 192.168.1.114.
  # OPNsense and predator are peer hosts on the home-router LAN (the
  # OPNsense laptop only has one ethernet port — it's not an inline
  # gateway). predator reaches OPNsense via the OPNsense WAN interface,
  # so OPNsense-side requirements are:
  #   - keep 192.168.1.114 stable (DHCP reservation on the home router,
  #     or set a static IP outside the router's DHCP pool)
  #   - Unbound listens on WAN (Services → Unbound DNS → Network Interfaces)
  #   - firewall rule allowing 192.168.1.0/24 → WAN address, TCP/UDP 53
  # Until those are done, DNS falls back to Quad9 via fallbackDns.
  #
  # `domains = [ "~." ]` forces all queries to the declared DNS server;
  # without it, DHCP-supplied DNS from the home router wins and OPNsense
  # never sees the queries.
  #
  # dnssec = "allow-downgrade" + dnsovertls = "opportunistic" because
  # OPNsense Unbound speaks plain DNS on the LAN side; strict "true"
  # would refuse the server and break resolution entirely.
  services.resolved = {
    enable      = true;
    dnssec      = "allow-downgrade";
    dnsovertls  = "opportunistic";
    llmnr       = "false"; # disable LLMNR — credential-theft surface (T1557.001)
    domains     = [ "~." ];
    fallbackDns = [
      "9.9.9.9"
      "149.112.112.112"
      "2620:fe::fe"
      "2620:fe::9"
    ];
    extraConfig = ''
      DNS=192.168.1.114
    '';
  };

  services.printing = {
    enable          = true;
    drivers         = with pkgs; [ gutenprint gutenprintBin hplip ];
    browsing        = false;                        # F-22: cupsd Browsing directive off
    listenAddresses = [ "localhost:631" ];          # F-22: bind only to loopback
  };

  # F-22: disable cups-browsed separately — `browsing = false` only controls cupsd;
  # cups-browsed is a separate unit (CVE-2024-47175 chain).
  systemd.services.cups-browsed.enable = lib.mkForce false;

  services.avahi = {
    enable       = true;
    nssmdns4     = true;
    openFirewall = true;   # needed for KDE Connect mDNS discovery
  };
}
