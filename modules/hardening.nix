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

    # extra hardening — prevent unprivileged userfaultfd (used in some kernel exploits)
    "vm.unprivileged_userfaultfd" = 0;

    # codex MEDIUM (base.nix:110): systemd.coredump.enable=false only stops systemd
    # from collecting dumps; the kernel will still write a `core` file in the process
    # CWD by default, which can leak memory contents (creds, tokens, decrypted secrets).
    # Pipe core dumps to /bin/false to discard them entirely at kernel level.
    "kernel.core_pattern" = "|/bin/false";
  };

  # F-20 (cross-kernel runtime hardening — works on stock or hardened kernel):
  # boot params applied even when boot.kernelPackages stays at default.
  # Hardened kernel sets most of these as defaults; redundant settings are harmless.
  boot.kernelParams = [
    "init_on_alloc=1"            # zero memory on alloc — defeats some uninit-memory exploits
    "init_on_free=1"             # zero memory on free — defeats UAF info-leak primitives
    "page_alloc.shuffle=1"       # randomize free list — defeats some heap-spray techniques
    "randomize_kstack_offset=on" # per-syscall kernel-stack offset randomization
    "vsyscall=none"              # disable legacy vsyscall ABI (reduces ROP gadget set)
    "slab_nomerge"               # don't merge slabs by size — defeats some heap exploits
  ];

  # F-23: enable AppArmor LSM framework. Profiles can be added incrementally;
  # this only loads the kernel module + ships upstream profiles in complain mode.
  security.apparmor = {
    enable                   = true;
    killUnconfinedConfinables = false;   # don't kill running processes that lose confinement at activation
    packages                 = [ pkgs.apparmor-profiles ];
  };
}
