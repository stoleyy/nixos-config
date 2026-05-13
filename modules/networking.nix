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
  # "loose" lets VPN return traffic through while still validating non-VPN
  # interfaces. "false" would also work but skips all rp_filter checking.
  networking.firewall.checkReversePath = "loose";

  # ProtonVPN via kernel WireGuard.
  # Uncomment + populate once secrets/secrets.yaml has a real protonvpn_wg_key
  # and the sops.secrets declaration in hosts/predator/default.nix is enabled.
  # Before enabling, replace PLACEHOLDER values with values from your downloaded
  # .conf file (account.protonvpn.com → Downloads → WireGuard configuration).
  #
  # networking.wg-quick.interfaces.vpn0 = {
  #   address         = [ "10.2.0.2/32" ];
  #   dns             = [ "10.2.0.1" ];
  #   privateKeyFile  = config.sops.secrets.protonvpn_wg_key.path;
  #   autostart       = false;
  #   peers = [
  #     {
  #       publicKey  = "PLACEHOLDER_SERVER_PUBKEY";
  #       allowedIPs = [ "0.0.0.0/0" "::/0" ];
  #       endpoint   = "PLACEHOLDER_SERVER_IP:51820";
  #     }
  #   ];
  # };

  # Quad9 via resolved. `domains = [ "~." ]` routes all queries to these servers
  # so DHCP-supplied DNS can't override them. `fallbackDns` only kicks in when
  # no link has DNS at all.
  services.resolved = {
    enable     = true;
    dnssec     = "true";
    dnsovertls = "true";
    llmnr      = "false";   # F15: disable LLMNR — credential-theft surface (T1557.001)
    domains    = [ "~." ];
    fallbackDns = [
      "9.9.9.9#dns.quad9.net"
      "149.112.112.112#dns.quad9.net"
      "2620:fe::fe#dns.quad9.net"
      "2620:fe::9#dns.quad9.net"
    ];
    extraConfig = ''
      DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net
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
