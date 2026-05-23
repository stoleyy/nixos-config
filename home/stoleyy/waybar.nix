{ colors, ... }:

{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 36;
        exclusive = true;
        margin-top = 4;
        margin-left = 8;
        margin-right = 8;

        # HyDE-inspired layout: leaf-inverse group left, pill center, leaf group right.
        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [
          "idle_inhibitor"
          "clock"
          "custom/notification"
        ];
        modules-right = [
          "mpris"
          "tray"
          "network"
          "bluetooth"
          "pulseaudio"
          "cpu"
          "memory"
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
          max-length = 40;
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
          format = "{:%I:%M %p}";
          format-alt = "{:%a %b %d, %Y}";
        };

        mpris = {
          format = "{player_icon} {dynamic}";
          format-paused = "{player_icon} <i>{dynamic}</i>";
          dynamic-order = [
            "title"
            "artist"
          ];
          dynamic-len = 25;
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
          format = "{icon}  {volume}%";
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
          format = "  {status}";
          format-connected = "  {device_alias}";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}";
          on-click = "blueman-manager";
        };

        network = {
          format-wifi = "  {essid}";
          format-ethernet = "󰈀  {ipaddr}";
          format-disconnected = "󰖪  Offline";
          tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr}/{cidr}\n {bandwidthUpBytes}  {bandwidthDownBytes}";
          tooltip-format-ethernet = "{ifname}\n{ipaddr}/{cidr}";
          on-click = "nm-connection-editor";
          interval = 5;
        };

        "custom/notification" = {
          tooltip = false;
          format = "{icon}";
          format-icons = {
            notification = "<span foreground='red'><sup></sup></span>";
            none = "";
            dnd-notification = "<span foreground='red'><sup></sup></span>";
            dnd-none = "";
            inhibited-notification = "<span foreground='red'><sup></sup></span>";
            inhibited-none = "";
            dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
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
          spacing = 10;
        };
      };
    };

    # HyDE-inspired CSS with pill/leaf group shapes and workspace expansion.
    style = ''
      @define-color bar-bg    rgba(29, 32, 33, 0.01);
      @define-color main-bg   rgba(29, 32, 33, 0.80);
      @define-color main-fg   ${colors.fg0};
      @define-color wb-act-bg rgba(152, 151, 26, 0.35);
      @define-color wb-act-fg ${colors.fg0};
      @define-color wb-hvr-bg rgba(215, 153, 33, 0.40);
      @define-color wb-hvr-fg ${colors.fg0};

      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size:   13px;
        border:      none;
        min-height:  0;
      }

      window#waybar {
        background-color: @bar-bg;
        color:            @main-fg;
      }

      tooltip {
        background:    @main-bg;
        border:        1px solid @wb-act-bg;
        border-radius: 10px;
        color:         @main-fg;
      }

      tooltip label {
        color:   @main-fg;
        padding: 4px;
      }

      /* ── Workspace expansion animation (HyDE signature) ── */
      #workspaces {
        background: @main-bg;
        border-radius: 10px 0 10px 0;  /* leaf-inverse shape */
        padding:    0 4px;
        margin:     3px 0 3px 3px;
      }

      #workspaces button {
        padding:          0 5px;
        background-color: transparent;
        color:            ${colors.muted};
        border-radius:    10px;
        margin:           3px 2px;
        transition:       padding 0.3s cubic-bezier(0.55, -0.68, 0.48, 1.682);
      }

      #workspaces button:hover {
        background: @wb-hvr-bg;
        color:      @wb-hvr-fg;
      }

      #workspaces button.active {
        padding:    0 12px;
        background: @wb-act-bg;
        color:      @wb-act-fg;
        font-weight: bold;
      }

      #workspaces button.urgent {
        background: rgba(204, 36, 29, 0.5);
        color:      ${colors.bright.red};
      }

      /* ── Left group: leaf-inverse (top-right + bottom-left rounded) ── */
      #window {
        background:    @main-bg;
        border-radius: 0 10px 0 10px;  /* leaf shape */
        padding:       0 12px;
        margin:        3px 0 3px 4px;
        color:         ${colors.fg1};
        font-style:    italic;
      }

      /* ── Center group: pill (fully rounded) ── */
      #idle_inhibitor,
      #clock,
      #custom-notification {
        padding: 0 10px;
        margin:  0;
        color:   @main-fg;
      }

      #idle_inhibitor {
        background:    @main-bg;
        border-radius: 10px 0 0 10px;
        padding-left:  14px;
        margin:        3px 0 3px 0;
      }

      #clock {
        background:    @main-bg;
        border-radius: 0;
        color:         ${colors.yellow};
        font-weight:   bold;
        margin:        3px 0;
      }

      #custom-notification {
        background:    @main-bg;
        border-radius: 0 10px 10px 0;
        padding-right: 14px;
        margin:        3px 0 3px 0;
      }

      /* ── Right group: leaf (top-left + bottom-right rounded) ── */
      #mpris,
      #tray,
      #network,
      #bluetooth,
      #pulseaudio,
      #cpu,
      #memory {
        background: @main-bg;
        padding:    0 10px;
        margin:     3px 0;
        color:      @main-fg;
      }

      #mpris {
        border-radius: 10px 0 10px 0;  /* leaf-inverse */
        margin-left:   3px;
        margin-right:  4px;
        color:         ${colors.bright.aqua};
      }

      #tray {
        border-radius: 0 10px 0 10px;  /* leaf */
        margin-right:  4px;
        padding:       0 8px;
      }

      #tray > .passive {
        -gtk-icon-effect: dim;
      }

      #network    {
        border-radius: 10px 0 0 10px;
        padding-left:  14px;
        color:         ${colors.blue};
      }
      #bluetooth  { color: ${colors.bright.orange}; }
      #pulseaudio { color: ${colors.bright.purple}; }
      #cpu        { color: ${colors.bright.green}; }
      #memory {
        border-radius: 0 10px 10px 0;
        padding-right: 14px;
        margin-right:  3px;
        color:         ${colors.bright.blue};
      }

      /* ── Hover for right group ── */
      #mpris:hover,
      #network:hover,
      #bluetooth:hover,
      #pulseaudio:hover,
      #cpu:hover,
      #memory:hover {
        background: @wb-hvr-bg;
        color:      @wb-hvr-fg;
      }
    '';
  };
}
