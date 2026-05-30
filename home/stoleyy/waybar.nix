{
  pkgs,
  lib,
  osConfig,
  theme,
  ...
}:

let
  inherit (theme) colors;

  gpuScript = pkgs.writeShellScript "waybar-gpu" ''
    smi=/run/current-system/sw/bin/nvidia-smi
    read -r temp power util <<< \
      "$($smi --query-gpu=temperature.gpu,power.draw,utilization.gpu \
         --format=csv,noheader,nounits 2>/dev/null | tr ',' ' ')"
    temp=''${temp:-0}; power=''${power:-0}; util=''${util:-0}
    printf '{"text":"󰢮 %s°C","tooltip":"GPU: %s°C | %.0fW | %s%%","class":"gpu"}\n' \
      "$temp" "$temp" "$power" "$util"
  '';

  vpnScript = pkgs.writeShellScript "waybar-vpn" ''
    if ${pkgs.iproute2}/bin/ip link show protonvpn &>/dev/null; then
      printf '{"text":"󰒄","tooltip":"ProtonVPN: connected","class":"connected"}\n'
    else
      printf '{"text":"󰦞","tooltip":"VPN disconnected","class":"disconnected"}\n'
    fi
  '';

  idsScript = pkgs.writeShellScript "waybar-ids" ''
    f="/var/log/vector/suricata-alerts-$(${pkgs.coreutils}/bin/date +%Y-%m-%d).json"
    if [[ ! -f "$f" ]] || [[ ! -s "$f" ]]; then
      ${pkgs.jq}/bin/jq -cn '{text:"󰒃",tooltip:"IDS: no alerts today",class:"clear"}'
      exit 0
    fi
    count=$(${pkgs.coreutils}/bin/wc -l < "$f" | ${pkgs.coreutils}/bin/tr -d ' ')
    last=$(${pkgs.coreutils}/bin/tail -1 "$f" \
      | ${pkgs.jq}/bin/jq -r '(.alert.signature // "unknown") + " | src " + (.src_ip // "?")')
    ${pkgs.jq}/bin/jq -cn \
      --arg t "󰒃 $count" \
      --arg tt "IDS: $count alert(s) today\nLast: $last" \
      --arg c "alert" \
      '{text:$t,tooltip:$tt,class:$c}'
  '';
in
{
  programs.waybar = {
    enable = true;
    systemd.enable = true; # auto-start + restart on crash
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
        # VPN/IDS indicators only appear when the matching system module is
        # actually active, so the bar stays honest on a host that doesn't run
        # ProtonVPN or Suricata (e.g. the gaming specialisation).
        modules-right = [
          "mpris"
          "custom/separator"
          "tray"
          "custom/separator"
        ]
        ++ lib.optional osConfig.modules.protonvpn.enable "custom/vpn"
        ++ lib.optional osConfig.services.suricata.enable "custom/ids"
        ++ [
          "network"
          "bluetooth"
          "pulseaudio"
          "custom/separator"
          "group/hardware"
          "custom/separator"
          "disk"
          "systemd-failed-units"
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
            notification = "<span foreground='${colors.yellow}'><sup></sup></span>";
            none = "";
            dnd-notification = "<span foreground='${colors.yellow}'><sup></sup></span>";
            dnd-none = "";
            inhibited-notification = "<span foreground='${colors.yellow}'><sup></sup></span>";
            inhibited-none = "";
            dnd-inhibited-notification = "<span foreground='${colors.yellow}'><sup></sup></span>";
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

        # ── New modules ──

        "custom/vpn" = {
          exec = toString vpnScript;
          return-type = "json";
          interval = 10;
          format = "{}";
        };

        "custom/ids" = {
          exec = toString idsScript;
          return-type = "json";
          interval = 15;
          format = "{}";
        };

        "custom/gpu" = {
          exec = toString gpuScript;
          return-type = "json";
          interval = 5;
          format = "{}";
        };

        # Hardware drawer — CPU visible, mem/temp/gpu expand on hover.
        "group/hardware" = {
          orientation = "inherit";
          drawer = {
            transition-duration = 300;
            transition-left-to-right = true;
          };
          modules = [
            "cpu"
            "memory"
            "temperature"
            "custom/gpu"
          ];
        };

        temperature = {
          interval = 5;
          critical-threshold = 85;
          format = " {temperatureC}°C";
          format-critical = " {temperatureC}°C";
        };

        disk = {
          interval = 30;
          format = "󰋊 {percentage_used}%";
          path = "/";
          tooltip-format = "Root: {used} / {total} ({percentage_used}%)\nFree: {free}";
        };

        # Hidden when all units are OK — only appears on failure.
        systemd-failed-units = {
          hide-on-ok = true;
          format = "  {nr_failed}";
          format-ok = "";
          system = true;
          user = true;
        };
      };
    };

    # Deltarune Sanctuary — floating island bar with glow accents.
    style = ''
      @define-color bg        transparent;
      @define-color mod-bg    alpha(${colors.bg1}, 0.75);
      @define-color mod-bg2   alpha(${colors.bg2}, 0.55);
      @define-color fg        ${colors.fg0};
      @define-color fg-dim    ${colors.fg2};
      @define-color fg-bright ${colors.fg1};
      @define-color accent    ${colors.yellow};
      @define-color accent2   ${colors.green};
      @define-color accent3   ${colors.blue};
      @define-color glow      alpha(${colors.yellow}, 0.25);
      @define-color glow-h    alpha(${colors.yellow}, 0.45);

      * {
        font-family: "${theme.font.name}";
        font-size:   ${toString theme.font.size}px;
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
        border:        1px solid alpha(${colors.green}, 0.2);
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
        border:      1px solid alpha(${colors.yellow}, 0.4);
        box-shadow:  0 0 8px @glow;
      }

      #workspaces button.urgent {
        background: alpha(${colors.red}, 0.5);
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
        border:        1px solid alpha(${colors.green}, 0.15);
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
        border:        1px solid alpha(${colors.yellow}, 0.25);
        box-shadow:    0 0 12px alpha(${colors.yellow}, 0.15);
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
        color:      alpha(${colors.muted}, 0.4);
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
        border:        1px solid alpha(${colors.yellow}, 0.15);
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
        box-shadow: 0 0 16px alpha(${colors.yellow}, 0.35);
      }

      #workspaces button.active:hover {
        box-shadow: 0 0 14px @glow-h;
      }

      /* ── Security cluster (VPN | IDS) ── */
      #custom-vpn {
        background:    @mod-bg;
        padding:       0 6px 0 10px;
        margin:        4px 0;
        border-radius: 12px 0 0 12px;
      }
      #custom-vpn.connected    { color: @accent2; }
      #custom-vpn.disconnected { color: ${colors.red}; }

      #custom-ids {
        background:    @mod-bg;
        padding:       0 10px 0 6px;
        margin:        4px 0;
        border-radius: 0 12px 12px 0;
        margin-right:  4px;
      }
      #custom-ids.clear { color: alpha(@accent2, 0.5); }
      #custom-ids.alert {
        color:      ${colors.red};
        font-weight: bold;
        box-shadow: 0 0 8px alpha(${colors.red}, 0.4);
      }

      /* ── GPU (inside drawer) ── */
      #custom-gpu {
        color: @fg-dim;
      }

      /* ── Temperature ── */
      #temperature {
        color: @fg-dim;
      }
      #temperature.critical {
        color: ${colors.red};
      }

      /* ── Disk ── */
      #disk {
        background:    @mod-bg;
        padding:       0 10px;
        margin:        4px 0;
        border-radius: 12px 0 0 12px;
        color:         @fg-dim;
      }

      /* ── Failed units (only visible when degraded) ── */
      #systemd-failed-units.degraded {
        background: @mod-bg;
        padding:    0 10px;
        margin:     4px 0;
        color:      ${colors.red};
        font-weight: bold;
      }
    '';
  };
}
