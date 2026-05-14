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
  # Wazuh manager listens on these ports (modules/wazuh-manager.nix):
  #   1515/TCP   agent registration
  #   55000/TCP  Wazuh manager API (dashboard talks to manager)
  #   443/TCP    dashboard web UI
  #   1514/UDP   agent log channel (events from registered agents)
  # Only opens these on the LAN side — predator is on 192.168.1.0/24 and reachable
  # only from there. From outside, agents must reach predator via the WireGuard
  # tunnel terminated on OPNsense, which then NAT-masquerades onto LAN.
  networking.firewall.allowedTCPPorts = [ 443 1515 55000 ];
  networking.firewall.allowedUDPPorts = [ 1514 ];
  # "loose" lets the WireGuard tunnel set up by Proton VPN (via NetworkManager)
  # return traffic through while still validating non-VPN interfaces. "false"
  # would also work but skips all rp_filter checking.
  networking.firewall.checkReversePath = "loose";

  # DNS goes to the OPNsense laptop running Unbound at 192.168.1.114.
  # OPNsense and predator are peer hosts on the home-router LAN (the
  # OPNsense laptop only has one ethernet port — it's not an inline
  # gateway). As of 2026-05-14 the OPNsense single NIC (ue0) is assigned
  # to the LAN role at 192.168.1.114/24; predator reaches it as a normal
  # LAN peer. OPNsense-side requirements:
  #   - 192.168.1.114 stable (static IP outside the home router's DHCP pool)
  #   - Unbound listens on LAN (Services → Unbound DNS → Network Interfaces)
  #   - default OPNsense LAN firewall is "allow all from LAN" so no extra rule needed
  # Until OPNsense is reachable, DNS falls back to Quad9 via fallbackDns.
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
