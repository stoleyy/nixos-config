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

    # F-18: also refuse "secure" (gateway-validated) redirects. Behind a NAT
    # no legitimate gateway redirect exists; closes the last redirect vector.
    "net.ipv4.conf.all.secure_redirects"     = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;

    # F-18: reverse path filtering — drop source-spoofed packets.
    # Value 2 (loose) validates that the source IP has any valid route, but
    # does not require the return path to be the same interface. This is
    # necessary for WireGuard (ProtonVPN): the VPN routes 0.0.0.0/0 through
    # the tunnel, creating asymmetric routing that strict (=1) rp_filter would
    # silently drop. Loose still rejects unroutable source IPs.
    "net.ipv4.conf.all.rp_filter"     = 2;
    "net.ipv4.conf.default.rp_filter" = 2;

    # F-18: refuse IP source-routed packets — classic IP-spoof / MITM vector.
    "net.ipv4.conf.all.accept_source_route"     = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route"     = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;

    # F-18: don't amplify ICMP echo broadcasts (Smurf) or respond to bogus
    # ICMP error replies.
    "net.ipv4.icmp_echo_ignore_broadcasts"       = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

    # F-18: log spoofed / source-routed / redirect packets
    "net.ipv4.conf.all.log_martians"     = 1;
    "net.ipv4.conf.default.log_martians" = 1;

    # F-18: TIME_WAIT assassination hardening
    "net.ipv4.tcp_rfc1337" = 1;

    # F-18: SYN cookies — kernel default, pinned so a future config can't drop it.
    "net.ipv4.tcp_syncookies" = 1;

    # F-19: filesystem TOCTOU protections (symlink/hardlink/fifo/regular)
    "fs.protected_symlinks"  = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_fifos"     = 2;
    "fs.protected_regular"   = 2;

    # F-19: refuse to write a core dump from suid/sgid binaries. Belt+suspenders
    # with the `kernel.core_pattern = "|/bin/false"` setting below.
    "fs.suid_dumpable" = 0;

    # prevent unprivileged userfaultfd (used in some kernel exploits)
    "vm.unprivileged_userfaultfd" = 0;

    # Pipe core dumps to /bin/false — discards them at kernel level to prevent
    # memory contents (creds, tokens) leaking via core files in the process CWD.
    "kernel.core_pattern" = "|/bin/false";

    # KSPP: hide kernel pointer values from unprivileged users — foils
    # /proc/kallsyms-based exploit reconnaissance.
    "kernel.kptr_restrict" = 2;

    # KSPP: only root can read dmesg — prevents kernel info disclosure to local users.
    "kernel.dmesg_restrict" = 1;

    # KSPP: disable kexec_load — closes a kernel-replacement privesc/persistence
    # path on a compromised root.
    "kernel.kexec_load_disabled" = 1;

    # KSPP: restrict ptrace via Yama LSM to descendants only. Stops the
    # "debugger scans all PIDs" attack against running browser/IDE/Wallet
    # processes. Value 1 keeps wine + gdb-on-own-PID working; 2/3 would break
    # gaming and game-mod tooling.
    "kernel.yama.ptrace_scope" = 1;

    # KSPP: force CAP_SYS_ADMIN for bpf(). eBPF has had multiple local-privesc
    # CVEs; making it root-only closes that class for unprivileged users.
    "kernel.unprivileged_bpf_disabled" = 1;

    # KSPP: harden the BPF JIT against Spectre-style speculative-exec attacks
    # targeting JIT'd BPF programs.
    "net.core.bpf_jit_harden" = 2;
  };

  # F-20: boot params that harden even the stock kernel.
  boot.kernelParams = [
    "init_on_alloc=1"
    "init_on_free=1"
    "page_alloc.shuffle=1"
    "randomize_kstack_offset=on"
    "vsyscall=none"
    "slab_nomerge"
    # Disable debugfs — kernel internals (PMU, IOMMU, tracing) aren't needed
    # for desktop use. chipsec uses its kernel module's own ioctl path, not
    # debugfs userspace, so SPI / BIOS / Secure-Boot diagnostics still work.
    "debugfs=off"
  ];

  # F-23: Profiles from `apparmor-profiles` load in their declared mode (typically
  # enforce). Use `aa-complain <profile>` post-boot to switch one to complain mode.
  security.apparmor = {
    enable                   = true;
    killUnconfinedConfinables = false;
    packages                 = [ pkgs.apparmor-profiles ];
  };

  # Defense-in-depth: only members of the `wheel` group can exec the sudo
  # binary. A local exploit landing exec as a non-wheel UID (nobody, daemon,
  # an unsandboxed service account) can't even invoke sudo to attempt privesc.
  # stoleyy is in `wheel` already (see modules/base.nix users.users.stoleyy).
  security.sudo.execWheelOnly = true;
}
