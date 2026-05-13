{ colors, ... }:

{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer    = "top";
        position = "top";
        height   = 30;
        spacing  = 4;

        modules-left   = [ "hyprland/workspaces" "hyprland/window" ];
        modules-center = [ "clock" ];
        modules-right  = [
          "cpu"
          "memory"
          "pulseaudio"
          "bluetooth"
          "network"
          "custom/notification"
          "tray"
        ];

        "hyprland/workspaces" = {
          format       = "{icon}";
          on-click     = "activate";
          format-icons = {
            "1"     = "1";
            "2"     = "2";
            "3"     = "3";
            "4"     = "4";
            "5"     = "5";
            active  = "";
            default = "";
            urgent  = "";
          };
          persistent-workspaces = {
            "*" = 5;
          };
        };

        "hyprland/window" = {
          max-length       = 40;
          separate-outputs = true;
        };

        clock = {
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          format         = " {:%H:%M}";
          format-alt     = " {:%a %b %d %Y}";
        };

        cpu = {
          format   = " {usage}%";
          tooltip  = false;
          interval = 2;
        };

        memory = {
          format   = " {}%";
          interval = 5;
        };

        pulseaudio = {
          format       = "{icon} {volume}%";
          format-muted = " muted";
          format-icons = {
            default = [ "" "" "" ];
          };
          on-click    = "pavucontrol";
          scroll-step = 1;
        };

        bluetooth = {
          format                              = " {status}";
          format-connected                    = " {device_alias}";
          tooltip-format                      = "{controller_alias}\t{controller_address}";
          tooltip-format-connected            = "{controller_alias}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected  = "{device_alias}";
          on-click                            = "blueman-manager";
        };

        network = {
          format-wifi             = " {essid} ({signalStrength}%)";
          format-ethernet         = " {ipaddr}/{cidr}";
          format-disconnected     = " Disconnected";
          tooltip-format-wifi     = "{essid}\n{ipaddr}/{cidr}\n {bandwidthUpBytes}   {bandwidthDownBytes}";
          tooltip-format-ethernet = "{ifname}\n{ipaddr}/{cidr}";
          on-click                = "nm-connection-editor";
          interval                = 5;
        };

        "custom/notification" = {
          tooltip      = false;
          format       = "{icon}";
          format-icons = {
            notification               = "<span foreground='red'><sup></sup></span>";
            none                       = "";
            dnd-notification           = "<span foreground='red'><sup></sup></span>";
            dnd-none                   = "";
            inhibited-notification     = "<span foreground='red'><sup></sup></span>";
            inhibited-none             = "";
            dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
            dnd-inhibited-none         = "";
          };
          return-type    = "json";
          exec-if        = "which swaync-client";
          exec           = "swaync-client -swb";
          on-click       = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          escape         = true;
        };

        tray = {
          spacing = 10;
        };
      };
    };

    style = ''
      * {
        font-family:   "JetBrainsMono Nerd Font";
        font-size:     13px;
        border:        none;
        border-radius: 0;
        min-height:    0;
      }

      window#waybar {
        background-color:    rgba(29, 32, 33, 0.9);
        color:               ${colors.fg0};
        transition-property: background-color;
        transition-duration: 0.5s;
      }

      #workspaces button {
        padding:          0 5px;
        background-color: transparent;
        color:            ${colors.muted};
        border-bottom:    3px solid transparent;
      }

      #workspaces button:hover {
        background: rgba(255, 255, 255, 0.05);
      }

      #workspaces button.active {
        color:         ${colors.green};
        border-bottom: 3px solid ${colors.green};
        font-weight:   bold;
      }

      #workspaces button.urgent {
        background-color: ${colors.red};
        color:            ${colors.fg0};
      }

      #clock,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #bluetooth,
      #tray,
      #custom-notification {
        padding:          0 10px;
        margin:           2px 2px;
        color:            ${colors.fg0};
        background-color: rgba(60, 56, 54, 0.8);
        border-radius:    6px;
      }

      #clock      { color: ${colors.yellow}; }
      #cpu        { color: ${colors.bright.green}; }
      #memory     { color: ${colors.bright.blue}; }
      #network    { color: ${colors.blue}; }
      #pulseaudio { color: ${colors.bright.purple}; }
      #bluetooth  { color: ${colors.bright.orange}; }

      #window {
        color:      ${colors.fg0};
        margin:     0 5px;
        font-style: italic;
      }

      tooltip {
        background: rgba(29, 32, 33, 0.9);
        border:     1px solid rgba(152, 151, 26, 0.5);
        color:      ${colors.fg0};
      }

      tooltip label {
        color: ${colors.fg0};
      }
    '';
  };
}
