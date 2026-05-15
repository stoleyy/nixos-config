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
      # the stable path on NVIDIA. Pairs with the X11 Plasma session below.
      wayland.enable = false;
    };

    # Plasma 6 X11 session is the default. The Plasma *Wayland* session is
    # kwin_wayland-backed and crashes the same way the SDDM Wayland greeter
    # did on this RTX 4070 + open-module stack: the Xorg greeter now shows
    # the login screen, but a Wayland session bounced straight back to it
    # (login → ~1s flash → SDDM). Full X11 (Xorg greeter + X11 Plasma) is
    # the stable NVIDIA path here. The Wayland session is still installed
    # and selectable from the SDDM session dropdown to retest after a
    # driver bump. Hyprland stays available via its specialisation entry.
    displayManager.defaultSession = "plasmax11";
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
