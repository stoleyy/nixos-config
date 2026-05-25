{ theme, ... }:

let
  inherit (theme) colors;
in
{
  programs.wlogout = {
    enable = true;
    layout = [
      {
        label = "lock";
        action = "hyprlock";
        text = "  Lock";
        keybind = "l";
      }
      {
        label = "logout";
        action = "loginctl terminate-user $USER";
        text = "󰍃  Logout";
        keybind = "e";
      }
      {
        label = "suspend";
        action = "systemctl suspend";
        text = "󰤄  Suspend";
        keybind = "u";
      }
      {
        label = "hibernate";
        action = "systemctl hibernate";
        text = "  Hibernate";
        keybind = "h";
      }
      {
        label = "shutdown";
        action = "systemctl poweroff";
        text = "  Shutdown";
        keybind = "s";
      }
      {
        label = "reboot";
        action = "systemctl reboot";
        text = "  Reboot";
        keybind = "r";
      }
    ];
    style = ''
      * {
        background-image: none;
        font-family:      "${theme.font.name}";
        font-size:        16px;
      }
      window {
        background-color: alpha(${colors.black}, 0.92);
      }
      button {
        color:            ${colors.fg0};
        background-color: alpha(${colors.bg1}, 0.6);
        border-style:     solid;
        border-width:     2px;
        border-color:     alpha(${colors.bg2}, 0.8);
        border-radius:    14px;
        margin:           14px;
        padding:          12px;
        transition:       all 0.3s ease;
      }
      button:focus,
      button:active,
      button:hover {
        background-color: alpha(${colors.green}, 0.35);
        border-color:     ${colors.green};
        outline-style:    none;
      }
    '';
  };
}
