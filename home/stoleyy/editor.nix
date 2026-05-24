{ pkgs, theme, ... }:

let
  inherit (theme) colors font;
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
          "editor.background" = colors.bg0;
          "sideBar.background" = colors.bg1;
          "activityBar.background" = colors.bg1;
          "titleBar.activeBackground" = colors.bg1;
          "tab.activeBackground" = colors.bg2;
          "tab.inactiveBackground" = colors.bg1;
          "statusBar.background" = colors.bg2;
          "terminal.background" = colors.bg0;
          "terminal.foreground" = colors.fg0;
          "editorGroupHeader.tabsBackground" = colors.bg1;
          "panel.background" = colors.bg0;
          "focusBorder" = colors.green;
          "list.activeSelectionBackground" = colors.green;
          "list.hoverBackground" = colors.bg2;
          "editor.selectionBackground" = "${colors.green}66";
          "editorCursor.foreground" = colors.yellow;
          "editor.lineHighlightBackground" = colors.bg1;
        };
        "editor.formatOnSave" = true;
        "editor.fontFamily" = "'${font.name}', monospace";
        "editor.fontSize" = font.size;
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
