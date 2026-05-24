{ pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        mkhl.direnv
        vscodevim.vim
      ];
      userSettings = {
        "workbench.colorTheme" = "Default Dark Modern";
        "workbench.colorCustomizations" = {
          "editor.background" = "#000000";
          "sideBar.background" = "#07062F";
          "activityBar.background" = "#07062F";
          "titleBar.activeBackground" = "#07062F";
          "tab.activeBackground" = "#0A094E";
          "tab.inactiveBackground" = "#07062F";
          "statusBar.background" = "#0A094E";
          "terminal.background" = "#000000";
          "terminal.foreground" = "#C8CAE0";
          "editorGroupHeader.tabsBackground" = "#07062F";
          "panel.background" = "#000000";
          "focusBorder" = "#3C4B9B";
          "list.activeSelectionBackground" = "#3C4B9B";
          "list.hoverBackground" = "#0A094E";
          "editor.selectionBackground" = "#3C4B9B66";
          "editorCursor.foreground" = "#5987C6";
          "editor.lineHighlightBackground" = "#07062F";
        };
        "editor.formatOnSave" = true;
        "editor.fontFamily" = "'JetBrainsMono Nerd Font', monospace";
        "editor.fontSize" = 13;
        "telemetry.telemetryLevel" = "off";
        "update.mode" = "none";
        "extensions.autoUpdate" = false;
        "extensions.autoCheckUpdates" = false;
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
        "nix.serverSettings".nixd = {
          formatting.command = [ "nixfmt" ];
          options.nixos.expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.predator.options";
          options.home_manager.expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.predator.config.home-manager.users.stoleyy.options";
        };
      };
    };
  };
}
