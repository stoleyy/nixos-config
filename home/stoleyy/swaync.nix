{ colors, ... }:

{
  xdg.configFile."swaync/config.json".text = builtins.toJSON {
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
    };
  };

  xdg.configFile."swaync/style.css".text = ''
    * {
      font-family: "JetBrainsMono Nerd Font";
      font-size:   13px;
    }

    .control-center,
    .notification-row .notification-background {
      background:    rgba(29, 32, 33, 0.95);
      color:         ${colors.fg0};
      border:        1px solid rgba(152, 151, 26, 0.3);
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
      background:    rgba(60, 56, 54, 0.6);
      color:         ${colors.fg0};
      border:        none;
      border-radius: 8px;
      padding:       6px 12px;
      transition:    all 0.2s ease;
    }

    .widget-title button:hover {
      background: rgba(152, 151, 26, 0.3);
    }

    .widget-dnd > switch:checked {
      background:    ${colors.green};
      border-radius: 8px;
    }

    .close-button {
      background:    rgba(214, 93, 14, 0.7);
      color:         ${colors.fg0};
      border:        none;
      border-radius: 6px;
      transition:    all 0.2s ease;
    }

    .close-button:hover {
      background: ${colors.orange};
    }
  '';
}
