{ pkgs, ... }:

{
  # F-18 + F-19: kernel runtime hardening via sysctl
  boot.kernel.sysctl = {
    # F-18: IPv6 Router Advertisement — disable for non-router workstations (mitm6 vector)
    "net.ipv6.conf.all.accept_ra"     = 0;
    "net.ipv6.conf.default.accept_ra" = 0;

    # F-18: ICMP redirect handling — workstations neither send nor accept
    "net.ipv4.conf.all.send_redirects"        = 0;
    "net.ipv4.conf.default.send_redirects"    = 0;
    "net.ipv4.conf.all.accept_redirects"      = 0;
    "net.ipv4.conf.default.accept_redirects"  = 0;
    "net.ipv6.conf.all.accept_redirects"      = 0;
    "net.ipv6.conf.default.accept_redirects"  = 0;

    # F-18: reverse path filtering — drop source-spoofed packets
    "net.ipv4.conf.all.rp_filter"     = 1;
    "net.ipv4.conf.default.rp_filter" = 1;

    # F-18: log spoofed / source-routed / redirect packets
    "net.ipv4.conf.all.log_martians"     = 1;
    "net.ipv4.conf.default.log_martians" = 1;

    # F-18: TIME_WAIT assassination hardening
    "net.ipv4.tcp_rfc1337" = 1;

    # F-19: filesystem TOCTOU protections (symlink/hardlink/fifo/regular)
    "fs.protected_symlinks"  = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_fifos"     = 2;
    "fs.protected_regular"   = 2;

    # prevent unprivileged userfaultfd (used in some kernel exploits)
    "vm.unprivileged_userfaultfd" = 0;

    # Pipe core dumps to /bin/false — discards them at kernel level to prevent
    # memory contents (creds, tokens) leaking via core files in the process CWD.
    "kernel.core_pattern" = "|/bin/false";
  };

  # F-20: boot params that harden even the stock kernel.
  boot.kernelParams = [
    "init_on_alloc=1"
    "init_on_free=1"
    "page_alloc.shuffle=1"
    "randomize_kstack_offset=on"
    "vsyscall=none"
    "slab_nomerge"
  ];

  # F-23: Profiles from `apparmor-profiles` load in their declared mode (typically
  # enforce). Use `aa-complain <profile>` post-boot to switch one to complain mode.
  security.apparmor = {
    enable                   = true;
    killUnconfinedConfinables = false;
    packages                 = [ pkgs.apparmor-profiles ];
  };
}
