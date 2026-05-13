{ pkgs, ... }:

let
  qdbus = "${pkgs.kdePackages.qttools}/bin/qdbus";
in
{
  programs.plasma = {
    enable = true;

    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop";
      colorScheme = "BladeeBlack";
      cursor = {
        theme = "Bibata-Modern-Classic";
        size = 24;
      };
      iconTheme = "Tela-circle-black-dark";
      wallpaperBackground = {
        color = "0,0,0";
      };
      clickItemTo = "open";
    };

    fonts = {
      general = {
        family = "Inter";
        pointSize = 10;
      };
      fixedWidth = {
        family = "GeistMono Nerd Font";
        pointSize = 11;
      };
      small = {
        family = "Inter";
        pointSize = 9;
      };
      menu = {
        family = "Inter";
        pointSize = 10;
      };
      toolbar = {
        family = "Inter";
        pointSize = 10;
      };
      windowTitle = {
        family = "Inter";
        pointSize = 10;
      };
    };

    hotkeys.commands = {
      "launch-brave" = {
        key = "Meta+B";
        command = "brave";
      };
      "launch-dolphin" = {
        key = "Meta+E";
        command = "dolphin";
      };
      "launch-terminal" = {
        key = "Meta+T";
        command = "ghostty";
      };
      "launch-spotify" = {
        key = "Meta+P";
        command = "spotify";
      };
      "toggle-panel" = {
        key = "Meta+Z";
        command = ''${qdbus} org.kde.plasmashell /PlasmaShell evaluateScript 'var ps=panels();for(var i=0;i<ps.length;i++){if(ps[i].location=="bottom"){ps[i].hiding=(ps[i].hiding=="none")?"autohide":"none";}}' '';
      };
    };

    shortcuts = {
      "services/org.kde.krunner.desktop"._launch = [
        "Meta"
        "Alt+Space"
      ];
      ksmserver = {
        "Lock Session" = "Meta+L";
        "Log Out" = "Ctrl+Alt+Del";
      };
      "services/org.kde.spectacle.desktop" = {
        "RectangularRegionScreenShot" = "Meta+Shift+S";
        "FullScreenScreenShot" = "Print";
        "ActiveWindowScreenShot" = "Meta+Print";
      };
      plasmashell = {
        "show-on-mouse-pos" = "Meta+V";
        "activate task manager entry 1" = [ ];
        "activate task manager entry 2" = [ ];
        "activate task manager entry 3" = [ ];
      };
      kwin = {
        "Show Desktop" = "Meta+D";
        "Overview" = "Meta+W";
        "Edit Tiles" = "Meta+Shift+T";
        "Switch to Desktop 1" = "Meta+1";
        "Switch to Desktop 2" = "Meta+2";
        "Switch to Desktop 3" = "Meta+3";
        "Window Quick Tile Left" = "Meta+Left";
        "Window Quick Tile Right" = "Meta+Right";
        "Window Quick Tile Top" = "Meta+Up";
        "Window Quick Tile Bottom" = "Meta+Down";
        "Window Maximize" = "Meta+PgUp";
        "Window Minimize" = "Meta+PgDown";
      };
    };

    panels = [
      {
        location = "bottom";
        height = 44;
        floating = true;
        hiding = "autohide";
        lengthMode = "fill";
        widgets = [
          {
            kickoff = {
              sortAlphabetically = true;
            };
          }
          {
            iconTasks = {
              launchers = [
                "applications:brave.desktop"
                "applications:org.kde.dolphin.desktop"
                "applications:com.mitchellh.ghostty.desktop"
                "applications:spotify.desktop"
              ];
            };
          }
          "org.kde.plasma.marginsseparator"
          {
            systemTray = {
              items.shown = [
                "org.kde.plasma.networkmanagement"
                "org.kde.plasma.bluetooth"
                "org.kde.plasma.volume"
                "org.kde.plasma.mediacontroller"
                "org.kde.kdeconnect"
                "org.kde.plasma.notifications"
              ];
            };
          }
          {
            digitalClock = {
              date.format = "isoDate";
              time.format = "24h";
            };
          }
        ];
      }
    ];

    kwin = {
      virtualDesktops = {
        number = 3;
        rows = 1;
        names = [
          "main"
          "web"
          "chat"
        ];
      };
      titlebarButtons.left = [ ];
      titlebarButtons.right = [
        "minimize"
        "maximize"
        "close"
      ];
      nightLight = {
        enable = true;
        mode = "automatic";
        temperature = {
          day = 6500;
          night = 4000;
        };
      };
    };

    krunner = {
      position = "center";
      historyBehavior = "enableSuggestions";
    };

    powerdevil.AC = {
      powerButtonAction = "showLogoutScreen";
      autoSuspend.action = "nothing";
      turnOffDisplay.idleTimeout = 480;
    };

    configFile = {
      "kwinrc"."org.kde.kdecoration2"."BorderSize" = "None";
      "kwinrc"."Windows"."BorderlessMaximizedWindows" = true;
      "kwinrc"."Compositing"."LatencyPolicy" = "Low";
      "kwinrc"."Compositing"."AllowTearing" = true;
      "klipperrc"."General"."MaxClipItems" = 30;
    };
  };
}
