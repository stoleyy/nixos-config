_:

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
        font-family:      "JetBrainsMono Nerd Font";
        font-size:        16px;
      }
      window {
        background-color: rgba(0, 0, 0, 0.92);
      }
      button {
        color:            #C8CAE0;
        background-color: rgba(7, 6, 47, 0.6);
        border-style:     solid;
        border-width:     2px;
        border-color:     rgba(10, 9, 78, 0.8);
        border-radius:    14px;
        margin:           14px;
        padding:          12px;
        transition:       all 0.3s ease;
      }
      button:focus,
      button:active,
      button:hover {
        background-color: rgba(60, 75, 155, 0.35);
        border-color:     #3C4B9B;
        outline-style:    none;
      }
    '';
  };
}
