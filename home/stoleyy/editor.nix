{ pkgs, ... }:

{
  programs.vscode = {
    enable  = true;
    package = pkgs.vscodium;
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        mkhl.direnv
        vscodevim.vim
      ];
      userSettings = {
        "editor.formatOnSave"      = true;
        "editor.fontFamily"        = "'JetBrainsMono Nerd Font', monospace";
        "editor.fontSize"          = 13;
        "telemetry.telemetryLevel" = "off";
        "update.mode"              = "none";
        "nix.enableLanguageServer" = true;
        "nix.serverPath"           = "nixd";
      };
    };
  };
}
