{ pkgs, lib, ... }:

{
  networking.networkmanager = {
    enable = true;
    dns    = "systemd-resolved";   # codex MEDIUM: explicit hand-off to resolved (was implicit/default)
  };
  networking.useDHCP       = false;
  networking.dhcpcd.enable = false;

  networking.firewall.enable          = true;
  networking.nftables.enable          = true;
  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ ];

  networking.nameservers = [
    "9.9.9.9#dns.quad9.net"
    "149.112.112.112#dns.quad9.net"
  ];

  services.resolved = {
    enable     = true;
    dnssec     = "true";
    dnsovertls = "true";
    llmnr      = "false";   # F15: disable LLMNR — credential-theft surface (T1557.001)
    fallbackDns = [
      "9.9.9.9#dns.quad9.net"
      "149.112.112.112#dns.quad9.net"
      "2620:fe::fe#dns.quad9.net"
      "2620:fe::9#dns.quad9.net"
    ];
  };

  # F01: hardened SSH — password auth disabled, root login prohibited, brute-force limited
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication        = false;
      PermitRootLogin               = "no";
      KbdInteractiveAuthentication  = false;
    };
    extraConfig = ''
      MaxAuthTries 3
      LoginGraceTime 30
    '';
  };

  services.fail2ban = {
    enable   = true;
    maxretry = 5;
    bantime  = "1h";
  };

  services.printing = {
    enable          = true;
    drivers         = with pkgs; [ gutenprint gutenprintBin hplip ];
    browsing        = false;                        # F-22: cupsd Browsing directive off
    listenAddresses = [ "localhost:631" ];          # F-22: explicit; bind only to loopback
  };

  # F-22: explicitly disable the cups-browsed.service systemd unit.
  # `services.printing.browsing = false` only controls cupsd's config; the
  # cups-browsed daemon (Sept 2024 CVE-2024-47175 chain) is a separate unit.
  systemd.services.cups-browsed.enable = lib.mkForce false;

  services.avahi = {
    enable       = true;
    nssmdns4     = true;
    openFirewall = true;
  };
}
