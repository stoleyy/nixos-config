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
