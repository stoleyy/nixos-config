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

  # The JSON-exec custom modules all share the same shape — one helper instead
  # of three near-identical attrsets.
  mkJson = exec: interval: {
    exec = toString exec;
    return-type = "json";
    inherit interval;
    format = "{}";
  };
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

        "custom/vpn" = mkJson vpnScript 10;
        "custom/ids" = mkJson idsScript 15;
        "custom/gpu" = mkJson gpuScript 5;

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

    # Deltarune Sanctuary — floating island bar.
    #
    # OLED burn-in: this bar is always-on and fixed-position, so persistent
    # high-luminance regions are the main burn-in vector on the G80SD.
    # Mitigations baked in here:
    #   - NO persistent box-shadow glows — every glow lives on :hover only.
    #   - The active-workspace pill uses a dimmed fill (full glow on hover).
    # Idle blanking (hypridle DPMS at 5 min) covers the away-from-keyboard
    # case; $mod+SHIFT+B hides the bar entirely for long static sessions.
    style = ''
      /* ── Palette tokens (single source — no inline alpha() below) ── */
      @define-color bg        transparent;
      @define-color mod-bg    alpha(${colors.bg1}, 0.75);
      @define-color mod-bg2   alpha(${colors.bg2}, 0.55);
      @define-color fg        ${colors.fg0};
      @define-color fg-dim    ${colors.fg2};
      @define-color fg-bright ${colors.fg1};
      @define-color accent    ${colors.yellow};
      @define-color accent2   ${colors.green};
      @define-color accent3   ${colors.blue};
      @define-color alert     ${colors.red};
      @define-color muted     ${colors.muted};
      /* Translucent edges + glows derived from the tokens above. */
      @define-color edge        alpha(@accent2, 0.20);
      @define-color edge-soft   alpha(@accent2, 0.15);
      @define-color edge-accent alpha(@accent, 0.25);
      @define-color edge-active alpha(@accent, 0.40);
      @define-color glow        alpha(@accent, 0.25);
      @define-color glow-h      alpha(@accent, 0.45);
      @define-color alert-glow  alpha(@alert, 0.40);

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
      tooltip label { color: @fg; padding: 5px; }

      .modules-left  { margin-left:  2px; }
      .modules-right { margin-right: 2px; }

      /* ── Shared island base (background + spacing for every module) ── */
      #workspaces, #window, #clock, #mpris, #tray, #network, #bluetooth,
      #pulseaudio, #cpu, #memory, #idle_inhibitor, #custom-notification,
      #custom-separator, #custom-vpn, #custom-ids, #disk {
        background:    @mod-bg;
        margin:        4px 0;
        padding:       0 10px;
        border-radius: 12px;
        color:         @fg;
      }

      /* ── Cluster radius caps, grouped by position ── */
      #network, #cpu, #idle_inhibitor, #disk, #custom-vpn {
        border-radius: 12px 0 0 12px;
      }
      #pulseaudio, #memory, #custom-notification, #custom-ids {
        border-radius: 0 12px 12px 0;
      }

      /* ── Workspaces ── */
      #workspaces {
        padding: 0 6px;
        margin:  4px 4px;
        border:  1px solid @edge;
      }
      #workspaces button {
        padding:       0 6px;
        background:    transparent;
        color:         @fg-dim;
        border-radius: 8px;
        margin:        3px 2px;
        transition:    all 0.3s cubic-bezier(0.55, -0.68, 0.48, 1.682);
      }
      #workspaces button:hover { background: @glow; color: @fg; }
      /* Active pill: dimmed persistent fill + border, no always-on glow. */
      #workspaces button.active {
        padding:     0 14px;
        background:  @glow;
        color:       @fg;
        font-weight: bold;
        border:      1px solid @edge-active;
      }
      #workspaces button.active:hover {
        background: @glow-h;
        box-shadow: 0 0 14px @glow-h;
      }
      #workspaces button.urgent { background: alpha(@alert, 0.5); color: @fg; }

      /* ── Window title ── */
      #window {
        padding:    0 14px;
        margin:     4px 4px;
        color:      @fg-dim;
        font-style: italic;
        border:     1px solid @edge-soft;
      }

      /* ── Clock (center island) — no persistent glow ── */
      #clock {
        padding:     0 18px;
        color:       @accent;
        font-weight: bold;
        font-size:   14px;
        border:      1px solid @edge-accent;
      }
      #clock:hover { box-shadow: 0 0 16px @glow-h; }

      /* ── Separator (thin dim pipe) ── */
      #custom-separator {
        color:     alpha(@muted, 0.4);
        padding:   0 2px;
        font-size: 10px;
      }

      /* ── mpris island ── */
      #mpris {
        margin-left: 4px;
        padding:     0 14px;
        color:       @accent;
        border:      1px solid @edge-accent;
      }

      /* ── Tray ── */
      #tray { padding: 0 6px; }
      #tray > .passive { -gtk-icon-effect: dim; }

      /* ── Status cluster (network → pulseaudio) ── */
      #network    { padding-left:  14px; color: @accent; }
      #bluetooth  { color: @accent2; }
      #pulseaudio { padding-right: 14px; color: @fg-bright; }

      /* ── System cluster (cpu + memory) ── */
      #cpu    { padding-left:  14px; color: @fg-dim; }
      #memory { padding-right: 14px; color: @fg-bright; }

      /* ── Controls cluster (inhibitor + notification) ── */
      #idle_inhibitor      { padding-left:  12px; color: @fg-dim; }
      #custom-notification { padding-right: 12px; margin-right: 4px; color: @fg-dim; }

      /* ── Hover glow (transient only) ── */
      #mpris:hover, #network:hover, #bluetooth:hover, #pulseaudio:hover,
      #cpu:hover, #memory:hover, #idle_inhibitor:hover,
      #custom-notification:hover {
        background: @glow;
        color:      @fg;
      }

      /* ── Security cluster (VPN | IDS) ── */
      #custom-vpn { padding: 0 6px 0 10px; }
      #custom-vpn.connected    { color: @accent2; }
      #custom-vpn.disconnected { color: @alert; }

      #custom-ids { padding: 0 10px 0 6px; margin-right: 4px; }
      #custom-ids.clear { color: alpha(@accent2, 0.5); }
      #custom-ids.alert {
        color:       @alert;
        font-weight: bold;
        box-shadow:  0 0 8px @alert-glow;
      }

      /* ── GPU + temperature (inside hardware drawer) ── */
      #custom-gpu  { color: @fg-dim; }
      #temperature { color: @fg-dim; }
      #temperature.critical { color: @alert; }

      /* ── Disk ── */
      #disk { color: @fg-dim; }

      /* ── Failed units (only visible when degraded) ── */
      #systemd-failed-units.degraded {
        background:  @mod-bg;
        padding:     0 10px;
        margin:      4px 0;
        color:       @alert;
        font-weight: bold;
      }
    '';
  };
}
