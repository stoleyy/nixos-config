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

  # DNS is provided by OPNsense (Unbound) via DHCP. resolved accepts the
  # DHCP-supplied server and forwards queries there. Quad9 is kept as a
  # fallback only for when no link has DNS at all.
  # dnsovertls = "opportunistic" and dnssec = "allow-downgrade" because
  # OPNsense Unbound speaks plain DNS (port 53) to LAN clients; strict
  # "true" / "true" would refuse to use any non-DoT server and break
  # resolution entirely when behind OPNsense.
  services.resolved = {
    enable      = true;
    dnssec      = "allow-downgrade";
    dnsovertls  = "opportunistic";
    llmnr       = "false"; # disable LLMNR — credential-theft surface (T1557.001)
    fallbackDns = [
      "9.9.9.9"
      "149.112.112.112"
      "2620:fe::fe"
      "2620:fe::9"
    ];
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
