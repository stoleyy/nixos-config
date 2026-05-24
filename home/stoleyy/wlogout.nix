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
        background-color: ${colors.black}EB;
      }
      button {
        color:            ${colors.fg0};
        background-color: ${colors.bg1}99;
        border-style:     solid;
        border-width:     2px;
        border-color:     ${colors.bg2}CC;
        border-radius:    14px;
        margin:           14px;
        padding:          12px;
        transition:       all 0.3s ease;
      }
      button:focus,
      button:active,
      button:hover {
        background-color: ${colors.green}59;
        border-color:     ${colors.green};
        outline-style:    none;
      }
    '';
  };
}
