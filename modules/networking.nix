# NetworkManager + nftables firewall, systemd-resolved with Quad9 DoT, ProtonVPN kill-switch support.
_:

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

  # All DNS goes to Quad9 over TLS (port 853), bypassing OPNsense Unbound.
  # Quad9 provides DNSSEC validation + threat-domain blocking.
  # strict DoT (dnsovertls = "true") = queries never fall back to plaintext.
  # fallbackDns is only reached if the primary DNS= list is entirely unreachable.
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

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true; # needed for KDE Connect mDNS discovery
    };
  };

}
