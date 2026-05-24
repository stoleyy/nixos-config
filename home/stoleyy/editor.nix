{ pkgs, theme, ... }:

let
  c = theme.colors;
  f = theme.font;
in
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
          "editor.background" = c.bg0;
          "sideBar.background" = c.bg1;
          "activityBar.background" = c.bg1;
          "titleBar.activeBackground" = c.bg1;
          "tab.activeBackground" = c.bg2;
          "tab.inactiveBackground" = c.bg1;
          "statusBar.background" = c.bg2;
          "terminal.background" = c.bg0;
          "terminal.foreground" = c.fg0;
          "editorGroupHeader.tabsBackground" = c.bg1;
          "panel.background" = c.bg0;
          "focusBorder" = c.green;
          "list.activeSelectionBackground" = c.green;
          "list.hoverBackground" = c.bg2;
          "editor.selectionBackground" = "${c.green}66";
          "editorCursor.foreground" = c.yellow;
          "editor.lineHighlightBackground" = c.bg1;
        };
        "editor.formatOnSave" = true;
        "editor.fontFamily" = "'${f.name}', monospace";
        "editor.fontSize" = f.size;
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
