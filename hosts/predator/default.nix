{ ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot = {
    enable             = true;
    configurationLimit = 20;
    editor             = false;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # 8 GB swapfile — install script places root on Samsung 980 Pro
  swapDevices = [ { device = "/swapfile"; size = 8192; } ];

  networking.hostName = "predator";
}
