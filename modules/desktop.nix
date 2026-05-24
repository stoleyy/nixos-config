# SDDM display manager, KDE Plasma 6 desktop, XDG portals, and session autologin wiring.
{ pkgs, ... }:

{
  services = {
    xserver.enable = true;
    desktopManager.plasma6.enable = true;
    displayManager = {
      sddm = {
        enable = true;
        # SDDM Wayland greeter: now retesting with open=true + fbdev=1.
        # Previously crashed on open module without fbdev=1 (reverted 59af7a7).
        # If it regresses (greeter flashes → text login), revert to false.
        wayland.enable = true;
      };

      # Hyprland is the default session. To switch: boot the "plasma"
      # specialisation from the systemd-boot menu (no autologin → SDDM greeter).
      defaultSession = "hyprland";

      # Autologin into the default session. SDDM stamps the last-used session
      # into the $HOME-shared ~/.local/share/sddm/state.conf on every login —
      # autologin included — and prefers that cache over defaultSession at the
      # greeter. $HOME is shared across specialisations, so without autologin
      # one specialisation's session choice would poison the cache for others.
      # Autologin skips the greeter and uses the configured Autologin.Session
      # (= defaultSession), making each boot entry deterministic regardless of
      # the cache: default → hyprland; plasma spec mkForce → plasma (greeter);
      # gaming-tuned spec mkForce → steam (gamescope).
      autoLogin = {
        enable = true;
        user = "stoleyy";
      };
    };
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
