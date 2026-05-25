# Declarative disk layout — disaster recovery spec for disko.
#
# NOT imported into the running config. To use:
#   1. Add `disko.url = "github:nix-community/disko"` to flake.nix inputs
#   2. Boot a NixOS installer ISO
#   3. `nix run github:nix-community/disko -- --mode destroy,format,mount ./hosts/predator/disko.nix`
#   4. `nixos-install --flake .#predator`
#
# Physical layout (Acer Predator PO3-650, 2x NVMe):
#   nvme0n1 — Samsung 980 Pro (~294 GB usable, was dual-boot, Windows removed)
#     p1: ESP (vfat, ~512 MB)
#     p4: root (ext4, ~294 GB, grown from 47.8 GB)
#   nvme1n1 — second NVMe (~1.5 TiB total)
#     p1: games (ext4, ~1.5 TiB at /home/stoleyy/games)
#     p2: data (ext4, remainder at /data)
#
# UUIDs from the running system (verified via blkid):
#   root:  af8035c3-bfc3-4674-b66d-1a5f0c1e8cce
#   boot:  BA72-1B01
#   games: efd6d32e-54f9-4e6d-965f-67279a31da47
#   data:  88c50d98-1905-405d-a9c2-5ce522c9ad77
#
# WARNING: partitions 2-3 on nvme0n1 are remnants of the old Windows install
# (recovery/MSR/etc.), now unused. A clean reinstall via disko would reclaim
# them, but the current layout works and resizing carried risk.
_: {
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0022"
                  "dmask=0022"
                ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [ "noatime" ];
              };
            };
          };
        };
      };
      nvme1 = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            games = {
              size = "1500G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/home/stoleyy/games";
                mountOptions = [
                  "noatime"
                  "nofail"
                  "x-systemd.device-timeout=5s"
                ];
              };
            };
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/data";
                mountOptions = [
                  "noatime"
                  "nofail"
                  "x-systemd.device-timeout=5s"
                ];
              };
            };
          };
        };
      };
    };
  };
}
