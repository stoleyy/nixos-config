# Qubes-style compartmentalization — GID-based network isolation + firejail offline vault.
# Apps in the "untrusted" group can reach the internet (via VPN) but NOT the LAN.
# KeePassXC runs with zero network access via firejail --net=none.
{ pkgs, ... }:

{
  # ── Group for LAN-isolated apps ──
  users.groups.untrusted = { };

  # ── Firejail for offline isolation (KeePassXC) ──
  programs.firejail = {
    enable = true;
    wrappedBinaries.keepassxc = {
      executable = "${pkgs.keepassxc}/bin/keepassxc";
      extraArgs = [
        "--net=none"
        "--noprofile"
      ];
    };
  };

  # ── nftables: block LAN for untrusted GID ──
  # Priority 50 fires AFTER the VPN kill switch (priority -100).
  # Kill switch allows LAN generally; this chain restricts it for untrusted GID.
  # Result: untrusted apps route through VPN (internet works) but can't scan LAN.
  systemd.services.compartments-nftables = {
    description = "Compartment isolation nftables rules";
    after = [
      "nftables.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "compartments-nft-load" ''
        ${pkgs.nftables}/bin/nft -f - <<'EOF'
        table inet compartments {
          chain output {
            type filter hook output priority 50; policy accept;
            meta skgid "untrusted" ip daddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 } counter drop
            meta skgid "untrusted" ip6 daddr { fd00::/8, fe80::/10 } counter drop
          }
        }
        EOF
      '';
      ExecStop = "${pkgs.nftables}/bin/nft delete table inet compartments";
    };
  };
}
