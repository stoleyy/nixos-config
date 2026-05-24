{ colors, ... }:

{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 38;
        exclusive = true;
        margin-top = 6;
        margin-left = 10;
        margin-right = 10;

        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [
          "clock"
        ];
        modules-right = [
          "mpris"
          "custom/separator"
          "tray"
          "custom/separator"
          "network"
          "bluetooth"
          "pulseaudio"
          "custom/separator"
          "cpu"
          "memory"
          "custom/separator"
          "idle_inhibitor"
          "custom/notification"
        ];

        "hyprland/workspaces" = {
          format = "{icon}";
          on-click = "activate";
          on-scroll-up = "hyprctl dispatch workspace e+1";
          on-scroll-down = "hyprctl dispatch workspace e-1";
          all-outputs = true;
          format-icons = {
            active = "";
            default = "";
            urgent = "";
          };
          persistent-workspaces = {
            "*" = 5;
          };
        };

        "hyprland/window" = {
          max-length = 35;
          separate-outputs = true;
        };

        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰅶";
            deactivated = "󰾪";
          };
        };

        clock = {
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          format = "  {:%I:%M %p}";
          format-alt = "  {:%a %b %d, %Y}";
        };

        mpris = {
          format = "{player_icon}  {dynamic}";
          format-paused = "{player_icon}  <i>{dynamic}</i>";
          dynamic-order = [
            "title"
            "artist"
          ];
          dynamic-len = 20;
          player-icons = {
            default = "▶";
            spotify = "";
            firefox = "";
            brave = "󰖟";
          };
          status-icons = {
            paused = "";
          };
        };

        cpu = {
          format = "  {usage}%";
          tooltip = false;
          interval = 2;
        };

        memory = {
          format = "  {}%";
          interval = 5;
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "  muted";
          format-icons = {
            headphone = "";
            default = [
              ""
              ""
              ""
            ];
          };
          on-click = "pavucontrol";
          scroll-step = 5;
        };

        bluetooth = {
          format = "";
          format-connected = " {num_connections}";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}";
          on-click = "blueman-manager";
        };

        network = {
          format-wifi = "  {signalStrength}%";
          format-ethernet = "󰈀";
          format-disconnected = "󰖪";
          tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr}/{cidr}\n {bandwidthUpBytes}  {bandwidthDownBytes}";
          tooltip-format-ethernet = "{ifname}\n{ipaddr}/{cidr}";
          on-click = "nm-connection-editor";
          interval = 5;
        };

        "custom/separator" = {
          format = "";
          tooltip = false;
        };

        "custom/notification" = {
          tooltip = false;
          format = "{icon}";
          format-icons = {
            notification = "<span foreground='#5987C6'><sup></sup></span>";
            none = "";
            dnd-notification = "<span foreground='#5987C6'><sup></sup></span>";
            dnd-none = "";
            inhibited-notification = "<span foreground='#5987C6'><sup></sup></span>";
            inhibited-none = "";
            dnd-inhibited-notification = "<span foreground='#5987C6'><sup></sup></span>";
            dnd-inhibited-none = "";
          };
          return-type = "json";
          exec-if = "which swaync-client";
          exec = "swaync-client -swb";
          on-click = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          escape = true;
        };

        tray = {
          spacing = 8;
          icon-size = 14;
        };
      };
    };

    # Deltarune Sanctuary — floating island bar with glow accents.
    style = ''
      @define-color bg        rgba(0, 0, 0, 0.0);
      @define-color mod-bg    rgba(7, 6, 47, 0.75);
      @define-color mod-bg2   rgba(10, 9, 78, 0.55);
      @define-color fg        #C8CAE0;
      @define-color fg-dim    #8D8FA7;
      @define-color fg-bright #B2B5CF;
      @define-color accent    #5987C6;
      @define-color accent2   #3C4B9B;
      @define-color accent3   #324DA7;
      @define-color glow      rgba(89, 135, 198, 0.25);
      @define-color glow-h    rgba(89, 135, 198, 0.45);

      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size:   13px;
        border:      none;
        min-height:  0;
      }

      window#waybar {
        background: @bg;
        color:      @fg;
      }

      tooltip {
        background:    @mod-bg;
        border:        1px solid @accent2;
        border-radius: 12px;
        color:         @fg;
      }

      tooltip label {
        color:   @fg;
        padding: 5px;
      }

      /* ── Floating island groups ── */
      .modules-left {
        margin-left: 2px;
      }

      .modules-right {
        margin-right: 2px;
      }

      /* ── Workspaces ── */
      #workspaces {
        background:    @mod-bg;
        border-radius: 12px;
        padding:       0 6px;
        margin:        4px 4px;
        border:        1px solid rgba(60, 75, 155, 0.2);
      }

      #workspaces button {
        padding:          0 6px;
        background:       transparent;
        color:            @fg-dim;
        border-radius:    8px;
        margin:           3px 2px;
        transition:       all 0.3s cubic-bezier(0.55, -0.68, 0.48, 1.682);
      }

      #workspaces button:hover {
        background: @glow;
        color:      @fg;
      }

      #workspaces button.active {
        padding:     0 14px;
        background:  @glow-h;
        color:       @fg;
        font-weight: bold;
        border:      1px solid rgba(89, 135, 198, 0.4);
        box-shadow:  0 0 8px @glow;
      }

      #workspaces button.urgent {
        background: rgba(155, 60, 60, 0.5);
        color:      @fg;
      }

      /* ── Window title ── */
      #window {
        background:    @mod-bg;
        border-radius: 12px;
        padding:       0 14px;
        margin:        4px 4px;
        color:         @fg-dim;
        font-style:    italic;
        border:        1px solid rgba(60, 75, 155, 0.15);
      }

      /* ── Clock (center island) ── */
      #clock {
        background:    @mod-bg;
        border-radius: 12px;
        padding:       0 18px;
        margin:        4px 0;
        color:         @accent;
        font-weight:   bold;
        font-size:     14px;
        border:        1px solid rgba(89, 135, 198, 0.25);
        box-shadow:    0 0 12px rgba(89, 135, 198, 0.15);
      }

      /* ── Right modules (shared base) ── */
      #mpris,
      #tray,
      #network,
      #bluetooth,
      #pulseaudio,
      #cpu,
      #memory,
      #idle_inhibitor,
      #custom-notification {
        background: @mod-bg;
        padding:    0 10px;
        margin:     4px 0;
        color:      @fg;
      }

      /* ── Separator (thin dim pipe) ── */
      #custom-separator {
        background: @mod-bg;
        color:      rgba(93, 94, 105, 0.4);
        padding:    0 2px;
        margin:     4px 0;
        font-size:  10px;
      }

      /* ── mpris island ── */
      #mpris {
        border-radius: 12px;
        margin-left:   4px;
        padding:       0 14px;
        color:         @accent;
        border:        1px solid rgba(89, 135, 198, 0.15);
      }

      /* ── Tray ── */
      #tray {
        padding: 0 6px;
      }

      #tray > .passive {
        -gtk-icon-effect: dim;
      }

      /* ── Status cluster (network → pulseaudio) ── */
      #network {
        border-radius: 12px 0 0 12px;
        padding-left:  14px;
        color:         @accent;
      }

      #bluetooth {
        color: @accent2;
      }

      #pulseaudio {
        border-radius: 0 12px 12px 0;
        padding-right: 14px;
        color:         @fg-bright;
      }

      /* ── System cluster (cpu + memory) ── */
      #cpu {
        border-radius: 12px 0 0 12px;
        padding-left:  14px;
        color:         @fg-dim;
      }

      #memory {
        border-radius: 0 12px 12px 0;
        padding-right: 14px;
        color:         @fg-bright;
      }

      /* ── Controls cluster (inhibitor + notification) ── */
      #idle_inhibitor {
        border-radius: 12px 0 0 12px;
        padding-left:  12px;
        color:         @fg-dim;
      }

      #custom-notification {
        border-radius: 0 12px 12px 0;
        padding-right: 12px;
        margin-right:  4px;
        color:         @fg-dim;
      }

      /* ── Hover glow ── */
      #mpris:hover,
      #network:hover,
      #bluetooth:hover,
      #pulseaudio:hover,
      #cpu:hover,
      #memory:hover,
      #idle_inhibitor:hover,
      #custom-notification:hover {
        background: @glow;
        color:      @fg;
      }

      #clock:hover {
        box-shadow: 0 0 16px rgba(89, 135, 198, 0.35);
      }

      #workspaces button.active:hover {
        box-shadow: 0 0 14px @glow-h;
      }
    '';
  };
}
