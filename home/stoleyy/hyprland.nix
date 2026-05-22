{ pkgs, ... }:

{
  home.packages = with pkgs; [
    swaynotificationcenter
    linux-wallpaperengine
    wl-clip-persist
    hyprpicker
    rofimoji
    grimblast
    grim
    slurp
    swayosd
    wl-clipboard
    cliphist
    udiskie
    playerctl
    brightnessctl
    libnotify
    pavucontrol
    blueman
    networkmanagerapplet
    polkit_gnome
    kitty
    imv
    hypridle
    kdePackages.kwallet
    kdePackages.kwallet-pam
  ];

  # Hypridle config — driven from Hyprland's exec-once (systemd.enable = false
  # below means no HM systemd service for it).
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
        lock_cmd        = hyprlock
        after_sleep_cmd = hyprctl dispatch dpms on
    }

    listener {
        timeout    = 300
        on-timeout = hyprlock
    }

    listener {
        timeout    = 600
        on-timeout = hyprctl dispatch dpms off
        on-resume  = hyprctl dispatch dpms on
    }
  '';

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    # systemd.enable = false: exec-once is the single source of truth for service
    # startup. Avoids hyprland-session.target race conditions on NVIDIA.
    systemd.enable = false;
    # Use the system hyprland from programs.hyprland.enable (avoids two copies).
    package = null;
    portalPackage = null;

    settings = {
      env = [
        "LIBVA_DRIVER_NAME,nvidia"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "WLR_NO_HARDWARE_CURSORS,1"
        "__GL_GSYNC_ALLOWED,1"
        "__GL_VRR_ALLOWED,1"
        "NIXOS_OZONE_WL,1"
        "MOZ_ENABLE_WAYLAND,1"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "XDG_SESSION_TYPE,wayland"
        "XDG_CURRENT_DESKTOP,Hyprland"
        # Reuse Plasma 6's Qt platform theme so Qt apps render Breeze under
        # Hyprland (matches their KDE appearance; no qt6ct/kvantum stack).
        "QT_QPA_PLATFORMTHEME,kde"
      ];

      exec-once = [
        # Wallpaper Engine wallpaper (workshop ID 3544773177) via the native
        # linux-wallpaperengine. Pinned to HDMI-A-1; --silent mutes audio.
        "linux-wallpaperengine --silent --screen-root HDMI-A-1 3544773177"
        "waybar"
        "swaync"
        "nm-applet --indicator"
        "cliphist wipe"
        "wl-paste --type text --watch cliphist store --max-items 50"
        "wl-paste --type image --watch cliphist store --max-items 50"
        "wl-clip-persist --clipboard regular"
        "swayosd-server"
        "udiskie --tray"
        "kdeconnect-indicator"
        "kwalletd6"
        "hypridle"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];

      monitor = [
        # Samsung Odyssey OLED G80SD on HDMI-A-1: 4K @ 240 Hz, 10-bit colour.
        # HDMI 2.1 with DSC is required to carry 4K@240@10bit; the RTX 4070 +
        # G80SD support it. If the link can't sustain 10-bit, drop `,bitdepth,10`.
        "HDMI-A-1,3840x2160@240,auto,1,bitdepth,10"
        # Wildcard fallback for any other connected output.
        ",preferred,auto,1"
      ];

      general = {
        gaps_in = 3;
        gaps_out = 8;
        border_size = 2;
        "col.active_border" = "rgba(d79921ff) rgba(98971aff) 45deg";
        "col.inactive_border" = "rgba(3c3836cc) rgba(504945cc) 45deg";
        layout = "dwindle";
        resize_on_border = true;
        snap.enabled = true;
        # Fullscreen tearing path — paired with an `immediate` window rule for
        # steam_app_.* below. Big input-latency win on the G80SD.
        allow_tearing = true;
      };

      decoration = {
        rounding = 10;
        active_opacity = 0.90;
        inactive_opacity = 0.80;
        fullscreen_opacity = 1;
        dim_inactive = false;
        dim_special = 0.3;
        blur = {
          enabled = true;
          size = 6;
          passes = 3;
          new_optimizations = true;
          ignore_opacity = true;
          xray = false;
          special = true;
        };
        shadow = {
          enabled = false;
        };
      };

      # Blur the waybar for frosted glass effect.
      layerrule = [
        "blur, waybar"
      ];

      # HyDE-inspired animation curves — wind for general, winIn/winOut for
      # open/close with distinct overshoot, liner for borders.
      animations = {
        enabled = true;
        bezier = [
          "wind,   0.05, 0.9,  0.1,  1.05"
          "winIn,  0.1,  1.1,  0.1,  1.1"
          "winOut, 0.3,  -0.3, 0,    1"
          "liner,  1,    1,    1,    1"
        ];
        animation = [
          "windows,     1, 6, wind,   slide"
          "windowsIn,   1, 6, winIn,  slide"
          "windowsOut,  1, 5, winOut, slide"
          "windowsMove, 1, 5, wind,   slide"
          "border,      1, 1, liner"
          "borderangle, 1, 30, liner, once"
          "fade,        1, 10, default"
          "workspaces,  1, 5, wind"
        ];
      };

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
        accel_profile = "flat";
      };

      cursor = {
        no_hardware_cursors = true;
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        mouse_move_enables_dpms = true;
        key_press_enables_dpms = true;
        # Adaptive Sync / VRR — pairs with __GL_VRR_ALLOWED=1 in env.
        vrr = 1;
        # Dark fallback colour shown briefly before the wallpaper engine
        # process renders — avoids a black flash at startup.
        background_color = "rgb(1d2021)";
      };

      # Hyprland 0.46+ removed `render.explicit_sync` — it's automatic now,
      # always on when the NVIDIA driver supports it. Removed.
      # Hyprland 0.46+ refactored `gestures.workspace_swipe(_fingers)` away.
      # Desktop has no touchpad anyway so the block is gone.

      debug = {
        disable_logs = true;
      };

      "$mod" = "SUPER";
      "$terminal" = "kitty";
      "$browser" = "brave";
      "$launcher" = "rofi -show drun";
      "$filemanager" = "dolphin";

      bind = [
        "$mod, Return, exec, $terminal"
        "$mod, B,      exec, $browser"
        "$mod, Space,  exec, $launcher"
        "$mod, E,      exec, $filemanager"
        "$mod, L,      exec, hyprlock"
        "$mod, V,      exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
        "$mod SHIFT, P, exec, hyprpicker -a"
        "$mod, period,  exec, rofimoji"
        "$mod SHIFT, E, exec, wlogout"

        "$mod, Q,      killactive"
        "$mod, F,      fullscreen"
        "$mod, P,      pseudo"
        "$mod, J,      togglesplit"
        "$mod SHIFT, Space, togglefloating"
        "$mod SHIFT, N, exec, swaync-client -t"

        "$mod, left,  movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up,    movefocus, u"
        "$mod, down,  movefocus, d"
        "$mod SHIFT, left,  movewindow, l"
        "$mod SHIFT, right, movewindow, r"
        "$mod SHIFT, up,    movewindow, u"
        "$mod SHIFT, down,  movewindow, d"

        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

        "$mod, S,       togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"

        ",      Print, exec, grimblast --notify copy area"
        "$mod,  Print, exec, grimblast --notify copy screen"
        "SHIFT, Print, exec, grimblast --notify copy output"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      bindel = [
        ",XF86AudioRaiseVolume,  exec, swayosd-client --output-volume raise"
        ",XF86AudioLowerVolume,  exec, swayosd-client --output-volume lower"
        ",XF86AudioMute,         exec, swayosd-client --output-volume mute-toggle"
        ",XF86MonBrightnessUp,   exec, swayosd-client --brightness raise"
        ",XF86MonBrightnessDown, exec, swayosd-client --brightness lower"
      ];

      bindl = [
        ",XF86AudioPlay, exec, playerctl play-pause"
        ",XF86AudioNext, exec, playerctl next"
        ",XF86AudioPrev, exec, playerctl previous"
      ];

      windowrulev2 = [
        "float, class:^(pavucontrol)$"
        "float, class:^(nm-connection-editor)$"
        "float, class:^(blueman-manager)$"
        "float, class:^(org.kde.polkit-kde-authentication-agent-1)$"
        "float, class:^(polkit-gnome-authentication-agent-1)$"
        "float, title:^(Picture-in-Picture)$"
        "keepaspectratio, title:^(Picture-in-Picture)$"
        "float, class:^(xdg-desktop-portal-gtk)$"
        "size 70% 70%, class:^(xdg-desktop-portal-gtk)$"
        # Tearing path for Steam game windows — lower input latency.
        "immediate, class:^(steam_app_.*)$"
      ];
    };
  };

  # HyDE-inspired hyprlock layout — time top-right, greeting center, input bottom.
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        grace = 5;
        hide_cursor = true;
      };
      background = [
        {
          path = "screenshot";
          blur_passes = 2;
          blur_size = 6;
          brightness = 0.5;
        }
      ];
      # Time — large, top-right.
      label = [
        {
          position = "-40, -20";
          halign = "right";
          valign = "top";
          color = "rgb(ebdbb2)";
          font_size = 90;
          font_family = "JetBrainsMono Nerd Font";
          text = ''cmd[update:1000] echo "$(date +"%H:%M")"'';
        }
        # Date — below time, top-right.
        {
          position = "-40, -150";
          halign = "right";
          valign = "top";
          color = "rgb(d5c4a1)";
          font_size = 22;
          font_family = "JetBrainsMono Nerd Font";
          text = ''cmd[update:60000] echo "$(date +"%A, %d %B %Y")"'';
        }
        # Greeting — center.
        {
          position = "0, 60";
          halign = "center";
          valign = "center";
          color = "rgb(d79921)";
          font_size = 18;
          font_family = "JetBrainsMono Nerd Font";
          text = ''cmd[update:60000] echo "Good $(date +%H | awk '{if ($1 < 12) print "Morning"; else if ($1 < 18) print "Afternoon"; else print "Evening"}'), $USER"'';
        }
      ];
      input-field = [
        {
          size = "200, 50";
          position = "0, -80";
          halign = "center";
          valign = "center";
          outline_thickness = 3;
          outer_color = "rgb(d79921)";
          inner_color = "rgb(1d2021)";
          font_color = "rgb(ebdbb2)";
          fade_on_empty = false;
          placeholder_text = "<i>Password...</i>";
          shadow_passes = 2;
        }
      ];
    };
  };
}
