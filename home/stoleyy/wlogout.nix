{ ... }:

{
  programs.wlogout = {
    enable = true;
    layout = [
      { label = "lock";      action = "hyprlock";                  text = "Lock";      keybind = "l"; }
      { label = "logout";    action = "loginctl terminate-user $USER"; text = "Logout";    keybind = "e"; }
      { label = "suspend";   action = "systemctl suspend";          text = "Suspend";   keybind = "u"; }
      { label = "hibernate"; action = "systemctl hibernate";        text = "Hibernate"; keybind = "h"; }
      { label = "shutdown";  action = "systemctl poweroff";         text = "Shutdown";  keybind = "s"; }
      { label = "reboot";    action = "systemctl reboot";           text = "Reboot";    keybind = "r"; }
    ];
    style = ''
      * {
        background-image: none;
        font-family:      "JetBrainsMono Nerd Font";
        font-size:        14px;
      }
      window {
        background-color: rgba(29, 32, 33, 0.9);
      }
      button {
        color:               #ebdbb2;
        background-color:    rgba(60, 56, 54, 0.8);
        border-style:        solid;
        border-width:        2px;
        border-color:        #3c3836;
        border-radius:       12px;
        margin:              10px;
      }
      button:focus,
      button:active,
      button:hover {
        background-color: rgba(152, 151, 26, 0.3);
        border-color:     #98971a;
        outline-style:    none;
      }
    '';
  };
}
