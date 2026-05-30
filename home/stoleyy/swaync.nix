{ theme, ... }:

let
  inherit (theme) colors;
in
{
  services.swaync = {
    enable = true;

    settings = {
      "$schema" = "/etc/xdg/swaync/configSchema.json";
      positionX = "right";
      positionY = "top";
      control-center-margin-top = 0;
      control-center-margin-bottom = 0;
      control-center-margin-right = 0;
      control-center-margin-left = 0;
      notification-icon-size = 64;
      notification-body-image-height = 100;
      notification-body-image-width = 200;
      timeout = 10;
      timeout-low = 5;
      timeout-critical = 0;
      fit-to-screen = true;
      control-center-width = 550;
      notification-window-width = 550;
      keyboard-shortcuts = true;
      image-visibility = "when-available";
      transition-time = 200;
      hide-on-clear = false;
      hide-on-action = true;
      script-fail-notify = true;
      widgets = [
        "inhibitors"
        "title"
        "mpris"
        "buttons-grid"
        "dnd"
        "notifications"
      ];
      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = " Clear All";
        };
        dnd = {
          text = "Do Not Disturb";
        };
        inhibitors = {
          text = "Inhibitors";
          button-text = "Clear All";
          active-hint = true;
          align-items = "left";
        };
        mpris = {
          image-size = 96;
          image-radius = 12;
        };
        # Quick actions — lock, screenshot, power menu, DND toggle.
        # swaync runs these via /bin/sh, so the binaries must be on PATH
        # (all shipped by the Hyprland session).
        "buttons-grid" = {
          actions = [
            {
              label = "󰌾";
              command = "loginctl lock-session";
            }
            {
              label = "󰹑";
              command = "grimblast copy area";
            }
            {
              label = "󰂜";
              command = "swaync-client --toggle-dnd --skip-wait";
            }
            {
              label = "󰐥";
              command = "wlogout";
            }
          ];
        };
      };
    };

    style = ''
      * {
        font-family: "${theme.font.name}";
        font-size:   ${toString theme.font.size}px;
      }

      .control-center,
      .notification-row .notification-background {
        background:    alpha(${colors.bg1}, 0.95);
        color:         ${colors.fg0};
        border:        1px solid alpha(${colors.green}, 0.35);
        border-radius: 14px;
      }

      .notification-row .notification-background {
        margin:  6px 8px;
        padding: 12px;
      }

      .notification-row .notification-background .notification {
        background: transparent;
        color:      ${colors.fg0};
      }

      .notification-row .notification-background .notification .notification-content {
        padding: 6px;
      }

      .notification-row .notification-background .notification .notification-content .summary {
        font-weight: bold;
        font-size:   14px;
        color:       ${colors.yellow};
      }

      .notification-row .notification-background .notification .notification-content .body {
        color: ${colors.fg1};
      }

      .notification-row .notification-background .notification .image {
        border-radius: 8px;
        margin-right:  8px;
      }

      .notification-row .notification-background.critical {
        border-color: ${colors.red};
        border-width: 2px;
      }

      .control-center {
        margin:  8px;
        padding: 12px;
      }

      .widget-title > label {
        font-weight: bold;
        font-size:   15px;
        color:       ${colors.yellow};
      }

      .widget-title button {
        background:    alpha(${colors.bg2}, 0.6);
        color:         ${colors.fg0};
        border:        none;
        border-radius: 8px;
        padding:       6px 12px;
        transition:    all 0.2s ease;
      }

      .widget-title button:hover {
        background: alpha(${colors.green}, 0.3);
      }

      .widget-dnd > switch:checked {
        background:    ${colors.blue};
        border-radius: 8px;
      }

      .widget-buttons-grid {
        padding:    8px;
        margin:     4px 0;
      }

      .widget-buttons-grid > flowbox > flowboxchild > button {
        background:    alpha(${colors.bg2}, 0.6);
        color:         ${colors.fg0};
        border:        none;
        border-radius: 10px;
        margin:        4px;
        padding:       10px;
        font-size:     18px;
        transition:    all 0.2s ease;
      }

      .widget-buttons-grid > flowbox > flowboxchild > button:hover {
        background: alpha(${colors.green}, 0.4);
      }

      .widget-mpris {
        padding: 8px;
      }

      .widget-mpris .widget-mpris-player {
        background:    alpha(${colors.bg2}, 0.5);
        border-radius: 12px;
        padding:       8px;
      }

      .widget-mpris .widget-mpris-title {
        font-weight: bold;
        color:       ${colors.fg0};
      }

      .widget-mpris .widget-mpris-subtitle {
        color: ${colors.fg2};
      }

      .close-button {
        background:    alpha(${colors.green}, 0.5);
        color:         ${colors.fg0};
        border:        none;
        border-radius: 6px;
        transition:    all 0.2s ease;
      }

      .close-button:hover {
        background: ${colors.blue};
      }
    '';
  };
}
