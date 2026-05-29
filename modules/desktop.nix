# SDDM display manager, XDG portals, session autologin wiring, and the
# (opt-in) KDE Plasma 6 desktop. Plasma is gated behind modules.plasma.enable
# and is only switched on by the `plasma` boot specialisation
# (hosts/predator/default.nix) — the default/daily generation is pure Hyprland.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.plasma;
in
{
  options.modules.plasma.enable = lib.mkEnableOption "KDE Plasma 6 desktop (only meant for the plasma boot specialisation)";

  config = lib.mkMerge [
    # ── Always-on login plumbing (Hyprland needs this too) ──
    {
      services = {
        xserver.enable = true;
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

      # KWallet auto-unlocks when its password matches the user login password.
      # `enableKwallet` hooks pam_kwallet5 into the named service's PAM stack —
      # it must be set on the services that *actually* authenticate. SDDM is the
      # graphical login for BOTH Hyprland and Plasma (Hyprland installs
      # kwallet + kwallet-pam in home-manager), so this hook stays unconditional
      # to keep wallet auto-unlock working in the pure-Hyprland default session.
      security.pam.services.sddm.enableKwallet = true;
    }

    # ── KDE Plasma 6 — opt-in (plasma specialisation only) ──
    (lib.mkIf cfg.enable {
      services.desktopManager.plasma6.enable = true;

      programs.kdeconnect.enable = true;

      # TTY login KWallet hook — Plasma-only companion to the sddm hook above.
      security.pam.services.login.enableKwallet = true;

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
    })
  ];
}
