# Kernel hardening — CIS/KSPP sysctl (network, ptrace, kptr) + AppArmor + secure boot settings.
{ pkgs, ... }:

{
  boot = {
    # F-18 + F-19: kernel runtime hardening via sysctl
    kernel.sysctl = {
      # F-18: IPv6 Router Advertisement — disable for non-router workstations (mitm6 vector)
      "net.ipv6.conf.all.accept_ra" = 0;
      "net.ipv6.conf.default.accept_ra" = 0;

      # F-18: ICMP redirect handling — workstations neither send nor accept
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;

      # F-18: also refuse "secure" (gateway-validated) redirects. Behind a NAT
      # no legitimate gateway redirect exists; closes the last redirect vector.
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;

      # F-18: refuse IP source-routed packets — classic IP-spoof / MITM vector.
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.default.accept_source_route" = 0;

      # F-18: don't amplify ICMP echo broadcasts (Smurf) or respond to bogus
      # ICMP error replies.
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # F-18: log spoofed / source-routed / redirect packets
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;

      # F-18: TIME_WAIT assassination hardening
      "net.ipv4.tcp_rfc1337" = 1;

      # F-18: SYN cookies — kernel default, pinned so a future config can't drop it.
      "net.ipv4.tcp_syncookies" = 1;

      # F-19: filesystem TOCTOU protections (symlink/hardlink/fifo/regular)
      "fs.protected_symlinks" = 1;
      "fs.protected_hardlinks" = 1;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;

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

      # Prevent auto-loading of TTY line disciplines — kernel exploit vector
      # (e.g. SLCAN, N_GSM). Lynis KRNL-6000.
      "dev.tty.ldisc_autoload" = 0;

      # KSPP: restrict perf_event to root — prevents unprivileged profiling
      # of kernel memory addresses, strengthening kptr_restrict=2 above.
      "kernel.perf_event_paranoid" = 3;
    };

    # F-20: boot params that harden even the stock kernel.
    # init_on_free=1 REMOVED: 5-8% wall-time overhead (24% system-time in
    # kernel compilation benchmarks — Kees Cook). With init_on_alloc=1 already
    # zeroing pages on allocation, init_on_free provides marginal use-after-free
    # defense at disproportionate cost. Amazon AL2023 enables alloc but not free.
    kernelParams = [
      "init_on_alloc=1"
      "page_alloc.shuffle=1"
      "randomize_kstack_offset=on"
      "vsyscall=none"
      "slab_nomerge"
      "debugfs=off"
    ];

    # CIS + NixOS hardened profile: blacklist obscure network protocols and
    # rarely-used filesystem drivers to reduce kernel attack surface.
    blacklistedKernelModules = [
      # Obscure network protocols with CVE histories
      "dccp"
      "sctp"
      "rds"
      "tipc"
      "ax25"
      "netrom"
      "rose"
      # Old/rare filesystems — never needed on this box
      "adfs"
      "affs"
      "bfs"
      "befs"
      "cramfs"
      "efs"
      # erofs intentionally NOT blacklisted — Flatpak's freedesktop runtime 23.08+
      # uses EROFS for image layers; blacklisting breaks Flatpak updates.
      "exofs"
      "freevxfs"
      "f2fs"
      "hfs"
      "hpfs"
      "jfs"
      "minix"
      "nilfs2"
      "omfs"
      "qnx4"
      "qnx6"
      "sysv"
      "ufs"
      # TTY line disciplines — CVE-2020-29660/29661, ldisc_autoload=0 blocks
      # auto-load but explicit modprobe still works without blacklisting
      "n_gsm"
      "n_hdlc"
      # CAN bus — not needed on a desktop
      "can_raw"
      # DMA attack vectors via FireWire/Thunderbolt
      "firewire-ohci"
      "thunderbolt"
    ];

    # `blacklist` only prevents auto-loading; `install … /bin/true` makes
    # explicit modprobe a no-op too — truly blocks the module.
    extraModprobeConfig = ''
      install dccp /bin/true
      install sctp /bin/true
      install rds /bin/true
      install tipc /bin/true
      install ax25 /bin/true
      install netrom /bin/true
      install rose /bin/true
      install adfs /bin/true
      install affs /bin/true
      install bfs /bin/true
      install befs /bin/true
      install cramfs /bin/true
      install efs /bin/true
      install exofs /bin/true
      install freevxfs /bin/true
      install f2fs /bin/true
      install hfs /bin/true
      install hpfs /bin/true
      install jfs /bin/true
      install minix /bin/true
      install nilfs2 /bin/true
      install omfs /bin/true
      install qnx4 /bin/true
      install qnx6 /bin/true
      install sysv /bin/true
      install ufs /bin/true
      install n_gsm /bin/true
      install n_hdlc /bin/true
      install can_raw /bin/true
      install firewire-ohci /bin/true
      install thunderbolt /bin/true
    '';
  };

  # F-23: Profiles from `apparmor-profiles` load in their declared mode (typically
  # enforce). Use `aa-complain <profile>` post-boot to switch one to complain mode.
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = true;
    packages = [ pkgs.apparmor-profiles ];
  };

  # Defense-in-depth: only members of the `wheel` group can exec the sudo
  # binary. A local exploit landing exec as a non-wheel UID (nobody, daemon,
  # an unsandboxed service account) can't even invoke sudo to attempt privesc.
  # stoleyy is in `wheel` already (see modules/base.nix users.users.stoleyy).
  security.sudo.execWheelOnly = true;

  # USBGuard — block unknown USB devices by default, allowlist known peripherals.
  # New devices are rejected until explicitly allowed with `usbguard allow-device <id>`.
  # Minor annoyance when plugging in new hardware = feature, not bug.
  services.usbguard = {
    enable = true;
    # Default policy for devices plugged in after boot.
    insertedDevicePolicy = "reject";
    # Devices present at boot are allowed (root hubs, built-in controllers).
    presentDevicePolicy = "allow";
    presentControllerPolicy = "allow";
    # Initial allowlist — generated from `lsusb` on this box (2026-05-24).
    # Format: allow id <vendor>:<product> name "<desc>"
    rules = ''
      allow id 1d6b:0002 name "Linux Foundation 2.0 root hub" with-interface equals { 09:00:00 }
      allow id 1d6b:0003 name "Linux Foundation 3.0 root hub" with-interface equals { 09:00:00 }
      allow id 046d:c54d name "Logitech USB Receiver"
      allow id 0461:4e99 name "Acer Elite USB Keyboard"
      allow id 8087:0033 name "Intel AX211 Bluetooth"
      # Sony DualShock 4
      allow id 054c:05c4
      allow id 054c:09cc
      # Sony DualSense (PS5)
      allow id 054c:0ce6
      # Sony DualSense Edge
      allow id 054c:0df2
      # USB mass storage (flash drives, external HDDs) — interface class 08:**
      allow with-interface equals { 08:*:* }
    '';
    IPCAllowedUsers = [ "root" ];
    IPCAllowedGroups = [ "wheel" ];
  };
}
