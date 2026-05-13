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
