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
    kitty
    imv
    hypridle

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
    # yazi: managed by programs.yazi in ./yazi.nix (gives us the Gruvbox theme)
    # walker: themed via xdg.configFile in ./walker.nix
    walker # Unified launcher (apps + clipboard + emoji + calc + window switch)
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
    command = "kitty --class scratchterm"
    class = "scratchterm"
    size = "60% 50%"
    margin = 50

    [scratchpads.btop]
    animation = "fromTop"
    command = "kitty --class scratchbtop -e btop"
    class = "scratchbtop"
    size = "70% 70%"
    margin = 50
  '';

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

    # Plugins matched to the system hyprland by virtue of being drawn from the
    # same nixpkgs pin (no separate hyprland-plugins flake input → no version
    # skew). All configs live under settings.plugin.<name> below.
    plugins = with pkgs.hyprlandPlugins; [
      hyprexpo # Mission Control–style workspace overview (Super + grave)
      hypr-dynamic-cursors # Cursor physics + shake-to-find (essential at 4K)
      borders-plus-plus # Concentric Gruvbox accent border
      hyprfocus # Subtle pulse on the newly-focused window
      hyprtrails # Motion trails behind moving windows
      xtra-dispatchers # Extra IPC dispatchers for richer binds
    ];

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
        # Belt-and-suspenders Qt scaling for non-Plasma Qt tools where
        # PLATFORMTHEME=kde doesn't carry Plasma's auto-scale heuristics.
        "QT_AUTO_SCREEN_SCALE_FACTOR,1"
        # XCURSOR_THEME / XCURSOR_SIZE / HYPRCURSOR_* are set by
        # home.pointerCursor at the top of this file — no manual env entries.
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
        # hyprsunset: OLED blue-light filter. Pre-shader, survives screen
        # captures, and is the documented successor to hyprshade. Daemon
        # mode auto-applies a sunset schedule based on system clock.
        "hyprsunset"
        # hyprpolkitagent: native Wayland polkit (supersedes polkit-gnome).
        "systemctl --user start hyprpolkitagent.service"
        # pyprland: scratchpads daemon. Config in xdg.configFile."hypr/pyprland.toml".
        "pypr"
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

      # Frosted-glass blur on every floating UI surface — without this,
      # launchers/notifications sit visually flat on top of the wallpaper
      # while waybar gets the glass treatment, an inconsistency.
      layerrule = [
        "blur, waybar"
        "blur, rofi"
        "blur, walker"
        "blur, wlogout"
        "blur, swaync-control-center"
        "blur, swaync-notification-window"
        # ignorezero stops the blur pass from sampling fully-transparent
        # pixels — saves a few ms per frame on the system tray and
        # eliminates blur "halos" around tray icons.
        "ignorezero, waybar"
        "ignorezero, swaync-notification-window"
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
          "windows,        1, 6,  wind,   slide"
          "windowsIn,      1, 6,  winIn,  slide"
          "windowsOut,     1, 5,  winOut, slide"
          "windowsMove,    1, 5,  wind,   slide"
          "border,         1, 1,  liner"
          "borderangle,    1, 30, liner,  once"
          "fade,           1, 10, default"
          "workspaces,     1, 5,  wind"
          # Vertical slide for pyprland scratchpads — matches their
          # "fromTop" animation hint in pyprland.toml.
          "specialWorkspace, 1, 5, wind, slidevert"
        ];
      };

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
        accel_profile = "flat";
        # Faster key repeat — 50 cps after 300 ms feels right for terminal +
        # text editing (default is 25/600). Numlock on by login (matches the
        # OS-level expectation for a desktop keyboard).
        repeat_rate = 50;
        repeat_delay = 300;
        numlock_by_default = true;
      };

      cursor = {
        no_hardware_cursors = true;
        # Sync cursor theme to gsettings so GNOME-toolkit apps see Bibata
        # without an explicit GTK setting.
        sync_gsettings_theme = true;
        # Warp cursor to the focused window when changing workspaces. Mode 2
        # = always; 1 = only if cursor would land off-screen.
        warp_on_change_workspace = 2;
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
        # Special (scratchpad) workspaces scale to 80% — gives the dropdown
        # terminal/btop scratchpads a clear visual offset from the desktop.
        special_scale_factor = 0.8;
        # Deterministic split direction: new windows always go to the right
        # of the active one, regardless of aspect ratio. Predictable layout.
        force_split = 2;
        use_active_for_splits = true;
      };

      binds = {
        # Pressing Super+<N> while already on workspace N returns to the
        # previous workspace. Combined with allow_workspace_cycles, this is
        # the same "back-and-forth" behaviour i3/sway users expect.
        workspace_back_and_forth = true;
        allow_workspace_cycles = true;
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
        background_color = "rgb(1d2021)";
        # Disable the X11-era middle-click-pastes-selection behaviour.
        # Almost always accidental; almost never intended.
        middle_click_paste = false;
        # Apps can't steal focus via XDG activation (e.g. firefox download
        # done, slack DM). They get an urgent border instead.
        focus_on_activate = false;
        # hyprlock survives a compositor crash — the lock screen persists
        # through the restart instead of dropping straight to the desktop.
        allow_session_lock_restore = true;
        # App-not-responding popup with a kill button (15 missed pings ≈ 7s
        # wedged) instead of a silently frozen window.
        enable_anr_dialog = true;
        anr_missed_pings = 15;
        # Terminal swallowing: when a GUI app is launched from a terminal,
        # the terminal window is hidden until the GUI exits. Lets `imv pic`
        # / `evince file.pdf` / `mpv vid` from kitty reuse the same tile.
        enable_swallow = true;
        swallow_regex = "^(kitty)$";
      };

      # Suppress the donation popup and the "new release news" popup that
      # would otherwise fire on each Hyprland version bump. Both are
      # Hyprland 0.42+ ecosystem-block settings.
      ecosystem = {
        no_donation_nag = true;
        no_update_news = true;
      };

      # Explicit off — there is no touchpad on this desktop; default depends
      # on libinput probing and being explicit avoids surprises if a USB
      # touchpad is ever plugged in.
      gestures = {
        workspace_swipe = false;
      };

      # NOTE on render.direct_scanout: JaKooLit (the NVIDIA-focused reference
      # config) keeps this off, and Hyprland defaults match. allow_tearing
      # = true (general block) already gives the lower-latency fullscreen
      # path with fewer NVIDIA side effects (no VRR-negotiation flicker on
      # partial redraws), so direct_scanout is intentionally absent here.

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
          bg_col = "rgb(1d2021)";
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

        # Concentric extra border in Gruvbox yellow — adds depth without
        # widening the main border. Plays nicely with `general.col.active_border`.
        borders-plus-plus = {
          add_borders = 1;
          "col.border_1" = "rgb(d79921)";
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

        # Motion trails in Gruvbox yellow. Cheap visual flair on 4K@240Hz.
        hyprtrails = {
          color = "rgba(d79921aa)";
          bezier_step = 0.025;
          points_per_step = 2;
          history_points = 20;
          history_step = 2;
        };
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
        "$mod, A,      exec, walker" # unified launcher (apps + clipboard + emoji)
        "$mod, E,      exec, $filemanager"
        "$mod, Y,      exec, $terminal -e yazi" # TUI file manager (kitty/ghostty graphics)
        "$mod, L,      exec, hyprlock"
        "$mod, V,      exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
        "$mod SHIFT, P, exec, hyprpicker -a"
        "$mod CTRL, P, exec, hyprprop | wl-copy" # window props -> clipboard
        "$mod, period,  exec, rofimoji"
        "$mod SHIFT, E, exec, wlogout"

        # Sidecars (Alt cluster)
        "$mod ALT, B, exec, rofi-bluetooth"
        "$mod ALT, R, exec, wl-screenrec -f $HOME/Videos/screen-$(date +%s).mp4"
        "$mod ALT SHIFT, R, exec, pkill -INT -x wl-screenrec"

        # pyprland scratchpads (Quake-style dropdowns)
        "$mod, T, exec, pypr toggle term" # dropdown ghostty
        "$mod, M, exec, pypr toggle btop" # dropdown system monitor

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
        # swapwindow: non-destructive position swap (preserves tree shape)
        "$mod ALT, left,  swapwindow, l"
        "$mod ALT, right, swapwindow, r"
        "$mod ALT, up,    swapwindow, u"
        "$mod ALT, down,  swapwindow, d"

        # Tabbed window grouping (i3-style stacked tabs in a single tile)
        "$mod, G,      togglegroup"
        "$mod, Tab,        changegroupactive, f"
        "$mod SHIFT, Tab,  changegroupactive, b"

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

        # movetoworkspacesilent: send the active window to workspace N
        # without switching to it. Standard "send to background" gesture.
        "$mod CTRL, 1, movetoworkspacesilent, 1"
        "$mod CTRL, 2, movetoworkspacesilent, 2"
        "$mod CTRL, 3, movetoworkspacesilent, 3"
        "$mod CTRL, 4, movetoworkspacesilent, 4"
        "$mod CTRL, 5, movetoworkspacesilent, 5"
        "$mod CTRL, 6, movetoworkspacesilent, 6"
        "$mod CTRL, 7, movetoworkspacesilent, 7"
        "$mod CTRL, 8, movetoworkspacesilent, 8"
        "$mod CTRL, 9, movetoworkspacesilent, 9"
        "$mod CTRL, 0, movetoworkspacesilent, 10"

        "$mod, S,       togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"

        ",      Print, exec, grimblast --notify copy area"
        "$mod,  Print, exec, grimblast --notify copy screen"
        "SHIFT, Print, exec, grimblast --notify copy output"
        # Annotated area capture: grimblast → satty editor → wl-copy on save.
        "$mod SHIFT, Print, exec, grimblast save area - | satty -f - --early-exit --copy-command wl-copy"

        # hyprexpo overview — Super + grave (backtick) toggles workspace grid.
        "$mod, grave, hyprexpo:expo, toggle"

        # Session submap entry — see the submap block in extraConfig below.
        "$mod, Escape, submap, session"
        ''$mod, Escape, exec, notify-send -t 4000 -u low " Session" "L lock  E exit  R reboot  S shutdown  U suspend\nEsc cancel"''
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

      # Session submap: $mod + Escape opens an inline modal where single
      # keys trigger lock/exit/reboot/shutdown/suspend. Action keys also
      # reset the submap (each is two binds — exec + submap reset).
      # Bound here in settings.bind; the submap definition itself is in
      # extraConfig below (submap blocks need raw, ordered config).
      windowrulev2 = [
        "float, class:^(pavucontrol)$"
        "float, class:^(nm-connection-editor)$"
        "float, class:^(blueman-manager)$"
        "float, class:^(org.kde.polkit-kde-authentication-agent-1)$"
        "float, class:^(polkit-gnome-authentication-agent-1)$"
        "float, class:^(hyprpolkitagent)$"
        "float, title:^(Picture-in-Picture)$"
        "pin,   title:^(Picture-in-Picture)$"
        "keepaspectratio, title:^(Picture-in-Picture)$"
        "float, class:^(xdg-desktop-portal-gtk)$"
        "size 70% 70%, class:^(xdg-desktop-portal-gtk)$"
        # GTK/Qt file picker dialogs: float, center, 70% of monitor.
        "float, title:^(Open File|Save As|Save File|Save Image)$"
        "size 70% 60%, title:^(Open File|Save As|Save File|Save Image)$"
        "center, title:^(Open File|Save As|Save File|Save Image)$"
        # Prevent hyprlock during fullscreen video / fullscreen games.
        "idleinhibit fullscreen, class:.*"
        # pyprland scratchpad classes: float + no animation on switch.
        "float, class:^(scratchterm|scratchbtop)$"
        # Tearing path for Steam game windows — lower input latency.
        "immediate, class:^(steam_app_.*)$"

        # HyDE-style per-class opacity tiers. The `override` flag bypasses
        # the global decoration.active_opacity/inactive_opacity for these
        # classes — gives a "depth" gradient: browsers slightly transparent,
        # productivity tools more so, games fully opaque.
        "opacity 0.95 override 0.85 override, class:^(firefox|Brave-browser|brave-browser|chromium)$"
        "opacity 0.90 override 0.80 override, class:^(kitty|ghostty|Code|code-oss|dolphin|org.kde.dolphin)$"
        "opacity 1.0 override 1.0 override,   class:^(steam_app_.*)$"
        "opacity 1.0 override 1.0 override,   title:^(.*Picture-in-Picture.*)$"
      ];
    };

    # Session-mode submap: declared as raw text because Hyprland's submap
    # blocks are sequential (each `submap = name` line scopes the binds
    # that follow it) and the HM Nix attrset doesn't preserve insertion
    # order. Each action key fires its command AND resets the submap, so
    # one keypress = one outcome + return-to-normal.
    extraConfig = ''
      submap = session
      bind = , L, exec, hyprlock
      bind = , L, submap, reset
      bind = , E, exec, loginctl terminate-user $USER
      bind = , E, submap, reset
      bind = , R, exec, systemctl reboot
      bind = , R, submap, reset
      bind = , S, exec, systemctl poweroff
      bind = , S, submap, reset
      bind = , U, exec, systemctl suspend
      bind = , U, submap, reset
      bind = , escape, submap, reset
      submap = reset
    '';
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
        # Now-playing — bottom. playerctl prints "title — artist" while
        # something is playing; the `|| echo` falls through to an empty
        # string when no MPRIS sender exists, hiding the label entirely.
        {
          position = "0, 80";
          halign = "center";
          valign = "bottom";
          color = "rgb(d5c4a1)";
          font_size = 14;
          font_family = "JetBrainsMono Nerd Font";
          text = "cmd[update:1000] playerctl --no-messages metadata --format ' {{title}} — {{artist}}' 2>/dev/null || echo";
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
