# LUKS-encrypted NVMe layout. LUKS containers opened in initrd; fileSystems
# reference /dev/mapper/* names. User data mounts (games, /data) live in
# hosts/predator/default.nix for nofail + device-timeout handling.
#
# UUID placeholders (6ebbc3fa-7297-48d3-bf7d-6d2a5a3fcb9c, etc.) are replaced by the migration
# script after cryptsetup luksFormat. See docs/superpowers/specs/2026-05-26-luks-migration-design.md.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "ahci"
        "xhci_pci"
        "nvme"
        "usbhid"
      ];
      # LOAD-BEARING — do NOT remove or move to availableKernelModules. VMD is
      # disabled in BIOS but the controller persists; the kernel still needs vmd
      # to find the root NVMe by-UUID, force-loaded here so it inits before
      # Stage-1 root discovery (6.12+). Removing it = unbootable "cannot find
      # root" (PR #8 tried -> #13 bricked -> #14 this fix). Regen clobbers it.
      kernelModules = [ "vmd" ];

      luks.devices = {
        # Passphrase-prompted at boot. Single prompt — the only interactive unlock.
        cryptroot = {
          device = "/dev/disk/by-uuid/6ebbc3fa-7297-48d3-bf7d-6d2a5a3fcb9c";
          allowDiscards = true; # TRIM for SSD performance
        };
        # Auto-unlocked by keyfile embedded in the initrd.
        cryptgames = {
          device = "/dev/disk/by-uuid/9cb83a31-102e-440f-9fea-f6c86dbefea8";
          keyFile = "/luks-keyfile";
          allowDiscards = true;
        };
        cryptdata = {
          device = "/dev/disk/by-uuid/25748fb8-febe-42af-9a95-98980ca89751";
          keyFile = "/luks-keyfile";
          allowDiscards = true;
        };
      };

      # Copy the keyfile from the root filesystem into the initrd at build time.
      # String path (not Nix path) so it resolves at activation, not eval.
      # During nixos-install this runs in the chroot (/mnt), finding /mnt/etc/luks-keyfile.
      secrets = {
        "/luks-keyfile" = "/etc/luks-keyfile";
      };
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
  };

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/22B6-803C";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
