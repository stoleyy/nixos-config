{ pkgs, ... }:

{
  services = {
    xserver.enable = true;
    desktopManager.plasma6.enable = true;
    displayManager.sddm = {
      enable = true;
      # SDDM greeter runs on Xorg, NOT Wayland. The Wayland greeter is
      # kwin_wayland-backed and crashes ~1s after start on this NVIDIA stack
      # (RTX 4070, open module) — confirmed in journalctl: "Greeter
      # started successfully" immediately followed by "Greeter stopped",
      # dropping the box to a text `predator login:`. The Xorg greeter is
      # the stable path on NVIDIA. The user's Plasma SESSION is still
      # Wayland (defaultSession = "plasma" below) — only the login screen
      # is X11.
      wayland.enable = false;
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
