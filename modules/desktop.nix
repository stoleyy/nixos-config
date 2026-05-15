{ pkgs, ... }:

{
  services = {
    xserver.enable = true;
    desktopManager.plasma6.enable = true;
    displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };

    # Plasma 6 Wayland is the default session; Hyprland stays available in the
    # SDDM session dropdown for occasional use.
    displayManager.defaultSession = "plasma";
  };

  programs.kdeconnect.enable = true;

  # KWallet auto-unlocks when its password matches the user login password.
  # `enableKwallet` hooks pam_kwallet5 into the named service's PAM stack —
  # it must be set on the services that *actually* authenticate (sddm for the
  # graphical login, login for TTYs); setting it on a non-authenticating
  # "kwallet" service alone is a no-op.
  security.pam.services = {
    sddm.enableKwallet = true;
    login.enableKwallet = true;
  };

  environment.systemPackages = with pkgs; [
    kdePackages.plasma-browser-integration
    # Plasma 6 CLI tools — by default these only live inside the Plasma
    # session PATH (pulled in transitively by plasma6), not in the system
    # PATH. Promoting them here so they're usable from external terminals
    # / TTYs / scripts for runtime introspection and tweaks:
    #   kreadconfig6 / kwriteconfig6  (kconfig)
    #   kquitapp6 / kcmshell6         (kdbusaddons)
    kdePackages.kconfig
    kdePackages.kdbusaddons
  ];
}
