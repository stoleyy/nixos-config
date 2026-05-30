{
  pkgs,
  theme,
  host,
  ...
}:

let
  inherit (theme) colors stripHash;
in

{
  home.packages = with pkgs; [

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

    imv
    hypridle
    btop

    # First-party hyprwm tools (replacements for older choices)
    hyprpolkitagent # Wayland-native polkit (replaces polkit_gnome)
    hyprsunset # Pre-shader blue-light filter (supersedes hyprshade)
    hyprcursor # SVG cursor runtime; pairs with hypr-dynamic-cursors
    hyprprop # Click-to-dump window props (hyprwm/contrib)

    # Scratchpads daemon (Quake-style dropdowns; config in xdg.configFile below)
    pyprland

    # Screenshot annotation + screen record
    satty
    wl-screenrec

    # Sidecar daily-driver tools
    xfce.thunar # Lightweight GTK file manager
    xfce.thunar-volman # Removable media integration
    xfce.tumbler # Thumbnail service for Thunar
    yazi # TUI file manager (Ghostty graphics-protocol previews)
    rofi-bluetooth # OLED-friendly keyboard-only BT pairing
    nwg-look # Wayland-native GTK theme verifier

    kdePackages.kwallet
    kdePackages.kwallet-pam
  ];

  # Unified pointer cursor: sets gtk + hyprcursor + XCursor env in one place.
  # Bibata-Modern-Classic at 32 px matches the 4K OLED scale. This replaces
  # the gtk.cursorTheme block in gtk.nix (kept for size correction below).
  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 32;
    gtk.enable = true;
    x11.enable = true;
    hyprcursor.enable = true;
  };

  # pyprland scratchpad config — TOML loaded by `pypr` daemon (exec-once below).
  # Each scratchpad is a class-tagged terminal window that toggles on a bind.
  xdg.configFile."hypr/pyprland.toml".text = ''
    [pyprland]
    plugins = ["scratchpads"]

    [scratchpads.term]
    animation = "fromTop"
    command = "ghostty --class=scratchterm"
    class = "scratchterm"
    size = "60% 50%"
    margin = 50

    [scratchpads.btop]
    animation = "fromTop"
    command = "ghostty --class=scratchbtop -e btop"
    class = "scratchbtop"
    size = "70% 70%"
    margin = 50
  '';

  # Hypridle config — driven from Hyprland's exec-once (systemd.enable = false
  # below means no HM systemd service for it).
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
        lock_cmd = pidof hyprlock || hyprlock
        before_sleep_cmd = loginctl lock-session
        after_sleep_cmd = hyprctl dispatch dpms on
    }

    # OLED burn-in prevention: blank the display after 5 minutes idle.
    # More aggressive than LCD — static UI elements (waybar, workspace
    # indicators) cause permanent damage on OLED over time.
    listener {
        timeout = 300
        on-timeout = hyprctl dispatch dpms off
        on-resume = hyprctl dispatch dpms on
    }

    # Lock after 10 minutes idle.
    listener {
        timeout = 600
        on-timeout = loginctl lock-session
    }
  '';

  wayland.windowManager.hyprland = {
    enable = true;
    # systemd.enable = false: exec-once is the single source of truth for service
    # startup. Avoids hyprland-session.target race conditions on NVIDIA.
    systemd.enable = false;
    # Use the system hyprland from programs.hyprland.enable (avoids two copies).
    package = null;
    portalPackage = null;

    # Plugins matched to the system hyprland by virtue of being drawn from the
    # same nixpkgs pin (no separate hyprland-plugins flake input → no version
    # skew). All configs live under settings.plugin.<name> below.
    plugins = with pkgs.hyprlandPlugins; [
      hyprexpo # Mission Control–style workspace overview (Super + grave)
      hypr-dynamic-cursors # Cursor physics + shake-to-find (essential at 4K)
      borders-plus-plus # Concentric Sanctuary accent border
      hyprfocus # Subtle pulse on the newly-focused window
      hyprtrails # Motion trails behind moving windows
      xtra-dispatchers # Extra IPC dispatchers for richer binds
    ];

    settings = {
      env = [
        # LIBVA_DRIVER_NAME and __GLX_VENDOR_LIBRARY_NAME are set system-wide
        # in modules/nvidia.nix via environment.sessionVariables — no duplication.
        # __GL_GSYNC_ALLOWED / __GL_VRR_ALLOWED removed: Hyprland controls VRR
        # at the DRM/KMS level (misc:vrr = 2); these OpenGL env vars conflict
        # with the compositor's VRR management (see nvidia.nix audit comment).
        "NIXOS_OZONE_WL,1"
        "MOZ_ENABLE_WAYLAND,1"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "XDG_SESSION_TYPE,wayland"
        "XDG_CURRENT_DESKTOP,Hyprland"
        # Reuse Plasma 6's Qt platform theme so Qt apps render Breeze under
        # Hyprland (matches their KDE appearance; no qt6ct/kvantum stack).
        "QT_QPA_PLATFORMTHEME,kde"
        # Belt-and-suspenders Qt scaling for non-Plasma Qt tools where
        # PLATFORMTHEME=kde doesn't carry Plasma's auto-scale heuristics.
        "QT_AUTO_SCREEN_SCALE_FACTOR,1"
        # XCURSOR_THEME / XCURSOR_SIZE / HYPRCURSOR_* are set by
        # home.pointerCursor at the top of this file — no manual env entries.
      ];

      exec-once = [
        # Signal systemd that the graphical session is live. systemd 258+
        # sets RefuseManualStart=yes on graphical-session.target, so we can't
        # start it directly. Instead we start our own hyprland-session.target
        # which BindsTo it (defined in systemd.user.targets below).
        "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP && systemctl --user start hyprland-session.target"

        # One-shots and self-supervising daemons. Long-running services
        # are managed by systemd user units (see systemd.user.services below)
        # for automatic crash restart.

        # Wallpaper Engine: managed by systemd (see systemd.user.services below).
        # waybar managed by systemd (programs.waybar.systemd.enable in waybar.nix)
        "nm-applet --indicator"
        "cliphist wipe"
        "udiskie --tray"
        "kdeconnect-indicator"
        "kwalletd6"
        "hypridle"
        # hyprsunset: OLED blue-light filter. Pre-shader, survives screen
        # captures, and is the documented successor to hyprshade. Daemon
        # mode auto-applies a sunset schedule based on system clock.
        "hyprsunset"
        # hyprpolkitagent: native Wayland polkit (supersedes polkit-gnome).
        "systemctl --user start hyprpolkitagent.service"
      ];

      monitor = [
        # Samsung Odyssey OLED G80SD on DP-2: 4K @ 240 Hz, 10-bit colour, HDR.
        # DP 1.4 with DSC carries 4K@240@10bit natively. If the link can't
        # sustain 10-bit, drop `,bitdepth,10`.
        #
        # `cm,hdr` puts the output into HDR via the wayland color-management
        # protocol (wp_color_management_v1, stable in Hyprland 0.49+ — no
        # `experimental:xx_color_management_v4` flag needed). Same KMS atomic
        # path KWin uses for HDR, which already works on this NVIDIA driver, so
        # gamescope's --hdr-enabled DRM-backend crash (#2081) does NOT apply
        # here. `sdrbrightness`/`sdrsaturation` keep SDR surfaces from looking
        # blown-out / washed-out once the output signal is HDR (1.0 = neutral;
        # raise sdrbrightness toward 1.2–1.4 if the SDR desktop looks dim).
        # If the desktop comes up washed-out or black, fall back to `cm,auto`
        # or drop the `cm,hdr,...` tail entirely and reload.
        "DP-2,3840x2160@240,auto,1,bitdepth,10,cm,hdr,sdrbrightness,1.0,sdrsaturation,1.0"
        # Wildcard fallback for any other connected output.
        ",preferred,auto,1"
      ];

      general = {
        gaps_in = 3;
        gaps_out = 8;
        border_size = 2;
        "col.active_border" = "rgba(${stripHash colors.green}ff) rgba(${stripHash colors.yellow}ff) 45deg";
        "col.inactive_border" = "rgba(${stripHash colors.bg1}cc) rgba(${stripHash colors.bg2}cc) 45deg";
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
        dim_special = 0.3;
        # Blur cost scales with output area; at 4K, passes=3/size=6 burns
        # 4-6 ms/frame of the 240 Hz budget and produces visible stutter
        # on heavy multitasking. passes=2/size=4 is imperceptibly different
        # on the frosted waybar but recovers the frame budget.
        blur = {
          enabled = true;
          size = 4;
          passes = 2;
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

      # Sanctuary animation curves — wind for general, winIn/winOut for
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
        accel_profile = "flat"; # Raw input — no acceleration curve (FPS gaming standard)
        sensitivity = 0; # Neutral — let the mouse DPI drive it (Superlight 2 HERO 2 sensor)
        scroll_factor = 3.0; # 3x scroll distance per wheel notch
      };

      cursor = {
        # Hardware cursors offload cursor rendering to the GPU's display engine,
        # saving a compositor pass each frame. Driver 580.x on NVIDIA handles
        # this correctly now. If cursors glitch or vanish, revert to true.
        no_hardware_cursors = false;
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
        # Adaptive Sync / VRR mode 2 = fullscreen-only. mode 1 enables VRR
        # on every surface and can dim / flicker on partial OLED redraws;
        # mode 2 keeps the gaming benefit and pins the desktop at 240 Hz.
        vrr = 2;
        # Dark fallback colour shown briefly before the wallpaper engine
        # process renders — avoids a black flash at startup.
        background_color = "rgb(${stripHash colors.black})";
      };

      # Lower-latency fullscreen on NVIDIA. The compositor bypasses its
      # own composition pass when a fullscreen client matches the output
      # mode exactly. Pairs with allow_tearing + the immediate window rule.
      render = {
        direct_scanout = true;
        # Fullscreen HDR passthrough: when an HDR game/video goes fullscreen,
        # hand its HDR signal straight to the (HDR) output instead of having
        # the compositor tone-map it. 2 = auto (only when the client's
        # colorspace matches the output), the safe value; 1 = always, 0 = off.
        # No-op while the desktop output is SDR.
        cm_fs_passthrough = 2;
      };

      # 4K HiDPI: prevent XWayland from upscaling legacy X11 apps (which
      # produces blurry text). With zero-scaling, X11 clients render at
      # native pixel resolution.
      xwayland = {
        force_zero_scaling = true;
      };

      # Mission Control–style workspace overview (hyprexpo plugin).
      # Bound to $mod + grave (backtick, top-left of keyboard) below.
      plugin = {
        hyprexpo = {
          columns = 3;
          gap_size = 5;
          bg_col = "rgb(${stripHash colors.black})";
          workspace_method = "center current";
          enable_gesture = false; # desktop has no touchpad
        };

        # Cursor physics + shake-to-find. The "shake" gesture briefly enlarges
        # the cursor when wiggled — a real ergonomic win at 4K where the
        # cursor is otherwise easy to lose. `tilt` mode rotates the cursor
        # subtly toward the direction of motion.
        dynamic-cursors = {
          enabled = true;
          mode = "tilt";
          threshold = 2;
          shake = {
            enabled = true;
            nearest = true;
            threshold = 6.0;
            base = 4.0;
            speed = 4.0;
            influence = 0.0;
            limit = 0.0;
            timeout = 2000;
            effects = false;
            ipc = false;
          };
        };

        # Concentric extra border in Sanctuary indigo — adds depth without
        # widening the main border. Plays nicely with `general.col.active_border`.
        borders-plus-plus = {
          add_borders = 1;
          "col.border_1" = "rgb(${stripHash colors.bg2})";
          border_size_1 = 1;
          natural_rounding = true;
        };

        # Subtle pulse on focus change. shrink_percentage 0.97 = barely
        # noticeable scale dip — enough to track focus, not enough to distract.
        hyprfocus = {
          enabled = true;
          keyboard_focus_animation = "shrink";
          mouse_focus_animation = "shrink";
          bezier = [
            "bezIn,  0.5, 0.0, 1.0, 0.5"
            "bezOut, 0.0, 0.5, 0.5, 1.0"
          ];
          shrink = {
            shrink_percentage = 0.97;
            in_bezier = "bezIn";
            in_speed = 0.4;
            out_bezier = "bezOut";
            out_speed = 0.4;
          };
        };

        # Motion trails in Sanctuary accent. Cheap visual flair on 4K@240Hz.
        hyprtrails = {
          color = "rgba(${stripHash colors.green}aa)";
          bezier_step = 0.025;
          points_per_step = 2;
          history_points = 20;
          history_step = 2;
        };
      };

      "$mod" = "SUPER";
      "$terminal" = "ghostty";
      "$browser" = "brave";
      "$launcher" = "rofi -show drun";
      "$filemanager" = "thunar";

      bind = [
        "$mod, Return, exec, $terminal"
        "$mod, B,      exec, $browser"
        "$mod, Space,  exec, $launcher"
        "$mod, E,      exec, $filemanager"
        "$mod, Y,      exec, $terminal -e yazi" # TUI file manager (ghostty graphics)
        "$mod CTRL, L,  exec, hyprlock"
        "$mod, V,      exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
        "$mod SHIFT, P, exec, hyprpicker -a"
        "$mod CTRL, P, exec, hyprprop | wl-copy" # window props -> clipboard
        "$mod, period,  exec, rofimoji"
        "$mod SHIFT, E, exec, wlogout"

        # Sidecars (Alt cluster)
        "$mod ALT, B, exec, rofi-bluetooth"
        "$mod ALT, R, exec, mkdir -p $HOME/Videos && wl-screenrec -f $HOME/Videos/screen-$(date +%s).mp4"
        "$mod ALT SHIFT, R, exec, pkill -INT -x wl-screenrec"

        # pyprland scratchpads (Quake-style dropdowns)
        "$mod, T, exec, pypr toggle term" # dropdown ghostty
        "$mod, M, exec, pypr toggle btop" # dropdown system monitor

        "$mod, Q,      killactive"
        "$mod, F,      fullscreen"
        "$mod, P,      pseudo"
        "$mod SHIFT, Space, togglefloating"

        # Vim-style focus (hjkl)
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r" # overrides hyprlock — use SUPER+CTRL+L instead

        # Vim-style move window
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        # Tab-style window cycling
        "$mod, Tab,       cyclenext"
        "$mod SHIFT, Tab, cyclenext, prev"
        "ALT, Tab,        cyclenext"
        "ALT SHIFT, Tab,  cyclenext, prev"

        # Workspace scroll (SUPER + mouse wheel)
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up,   workspace, e-1"
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
        "$mod,  Print, exec, grimblast --notify copysave screen $HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"
        "SHIFT, Print, exec, grimblast --notify copysave output $HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"
        # Annotated area capture: grimblast → satty editor → wl-copy on save.
        "$mod SHIFT, Print, exec, grimblast save area - | satty -f - --early-exit --copy-command wl-copy"

        # hyprexpo overview — Super + grave (backtick) toggles workspace grid.
        "$mod, grave, hyprexpo:expo, toggle"
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

        "float, title:^(Picture-in-Picture)$"
        "keepaspectratio, title:^(Picture-in-Picture)$"
        "float, class:^(xdg-desktop-portal-gtk)$"
        "size 70% 70%, class:^(xdg-desktop-portal-gtk)$"
        # Tearing path — lower input latency for all games (Steam, Wine, Lutris,
        # gamescope, non-Steam games added via game-install pipeline).
        "immediate, class:^(steam_app_.*)$"
        "immediate, class:^(wine)$"
        "immediate, class:^(lutris)$"
        "immediate, class:^(gamescope)$"
        "immediate, class:^(.*.exe)$"
        # Force full opacity on video/media players.
        "opacity 1.0 override 1.0 override, class:^(mpv)$"
        "opacity 1.0 override 1.0 override, class:^(vlc)$"
        "opacity 1.0 override 1.0 override, class:^(com.stremio.stremio)$"
        "opacity 1.0 override 1.0 override, title:^(Picture-in-Picture)$"
        "opacity 1.0 override 1.0 override, class:^(brave-browser)$"
        "opacity 1.0 override 1.0 override, class:^(greenlight-desktop)$"
        "opaque, class:^(greenlight-desktop)$"
        # ── Qubes-style trust domain borders ──
        # Green = sensitive/credentials (vault, KeePassXC)
        "bordercolor rgb(2E7D32), class:^(brave-vault)$"
        "bordercolor rgb(2E7D32), class:^(org.keepassxc.KeePassXC)$"
        # Indigo = standard daily use (personal)
        "bordercolor rgb(0A094E), class:^(brave-personal)$"
        # Red = untrusted (LAN blocked, don't trust)
        "bordercolor rgb(C62828), class:^(brave-untrusted)$"
        "bordercolor rgb(C62828), class:^(discord)$"
        # Orange = ephemeral (wiped on exit)
        "bordercolor rgb(F57C00), class:^(brave-disposable)$"
      ];
    };
  };

  # hyprland-session.target — systemd 258+ compatible session activation.
  # graphical-session.target has RefuseManualStart=yes, so we can't start it
  # directly from exec-once. This target acts as the bridge: exec-once starts
  # it, and BindsTo pulls in graphical-session.target (which pulls in waybar,
  # swaync, cliphist, etc.).
  systemd.user.targets.hyprland-session = {
    Unit = {
      Description = "Hyprland compositor session";
      BindsTo = [ "graphical-session.target" ];
      After = [ "graphical-session-pre.target" ];
      Wants = [ "graphical-session-pre.target" ];
    };
  };

  # Long-running Hyprland session services supervised by systemd for automatic
  # crash restart. These replace the equivalent exec-once entries.
  # swaync is managed by services.swaync.enable in swaync.nix (HM-native systemd unit).
  systemd.user.services =
    let
      # Shared service template for Hyprland session daemons.
      # Restarts on crash up to 5 times in 60s, then gives up.
      mkSessionService = desc: cmd: {
        Unit = {
          Description = desc;
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          StartLimitBurst = 5;
          StartLimitIntervalSec = 60;
        };
        Service = {
          ExecStart = cmd;
          Restart = "on-failure";
          RestartSec = "5s";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    in
    {
      swayosd = mkSessionService "SwayOSD server" "${pkgs.swayosd}/bin/swayosd-server";
      cliphist-text = mkSessionService "Clipboard history (text)" "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store --max-items 50";
      cliphist-image = mkSessionService "Clipboard history (images)" "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store --max-items 50";
      wl-clip-persist = mkSessionService "Persist clipboard on app close" "${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard regular";
      pyprland = mkSessionService "Pyprland scratchpad daemon" "${pkgs.pyprland}/bin/pypr";
      wallpaper-engine = {
        Unit = {
          Description = "Wallpaper Engine (linux-wallpaperengine)";
          After = [ "hyprland-session.target" ];
          PartOf = [ "hyprland-session.target" ];
          StartLimitBurst = 5;
          StartLimitIntervalSec = 60;
        };
        Service = {
          Environment = [
            "XDG_SESSION_TYPE=wayland"
            "XDG_CURRENT_DESKTOP=Hyprland"
          ];
          ExecStart = "${pkgs.linux-wallpaperengine}/bin/linux-wallpaperengine --silent --screen-root ${host.monitor} 3510055857";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        Install.WantedBy = [ "hyprland-session.target" ];
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
          color = "rgb(${stripHash colors.fg0})";
          font_size = 90;
          font_family = theme.font.name;
          text = ''cmd[update:1000] echo "$(date +"%H:%M")"'';
        }
        # Date — below time, top-right.
        {
          position = "-40, -150";
          halign = "right";
          valign = "top";
          color = "rgb(${stripHash colors.fg1})";
          font_size = 22;
          font_family = theme.font.name;
          text = ''cmd[update:60000] echo "$(date +"%A, %d %B %Y")"'';
        }
        # Greeting — center.
        {
          position = "0, 60";
          halign = "center";
          valign = "center";
          color = "rgb(${stripHash colors.yellow})";
          font_size = 18;
          font_family = theme.font.name;
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
          outer_color = "rgb(${stripHash colors.green})";
          inner_color = "rgb(${stripHash colors.bg1})";
          font_color = "rgb(${stripHash colors.fg0})";
          fade_on_empty = false;
          placeholder_text = "<i>Password...</i>";
          shadow_passes = 2;
        }
      ];
    };
  };
}
