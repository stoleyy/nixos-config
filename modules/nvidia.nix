{ config, lib, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable      = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      nvidia-vaapi-driver
      libva
      libvdpau-va-gl
    ];
    # F12: pkgsi686Linux.nvidia-vaapi-driver removed — package has no 32-bit build,
    # would block predator evaluation. extraPackages32 left empty for future 32-bit deps.
    extraPackages32 = [ ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open               = true;
    nvidiaSettings     = true;

    powerManagement.enable      = true;
    powerManagement.finegrained = false;

    # Production driver — best Wayland + Ada (RTX 4070) combination in 2025/26.
    # `production` lags `stable` by a few weeks but has stronger Wayland/HDR
    # validation. If a regression hits, fall back to `stable`.
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME         = "nvidia";
    NVD_BACKEND               = "direct";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # F11: MOZ_DISABLE_RDD_SANDBOX removed — disabling Firefox's RDD sandbox is a
    # security regression that was a workaround for older NVIDIA driver paths.
    # 560+ open kernel modules + nvidia-vaapi-driver 0.0.13+ no longer require it.
    NIXOS_OZONE_WL            = "1";
  };

  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
  ];

  # Preserve VRAM across suspend — prevents corrupted display on resume on Ada.
  boot.extraModprobeConfig = ''
    options nvidia NVreg_PreserveVideoMemoryAllocations=1
  '';
}
