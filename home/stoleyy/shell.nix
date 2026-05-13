{ ... }:

{
  programs.fish = {
    enable = true;
    shellAliases = {
      ll   = "ls -lah";
      nb   = "nh os switch";
      cat  = "bat";
      grep = "rg";
    };
    # F-24 (v2): aliases can't reliably hold (hostname) substitution in fish.
    # Define `rebuild` as a function so command substitution evaluates at runtime.
    functions = {
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#(hostname)";
    };
    interactiveShellInit = "set -U fish_greeting";
  };

  programs.starship.enable = true;

  programs.atuin = {
    enable                = true;
    enableFishIntegration = true;
    settings = {
      auto_sync    = false;
      update_check = false;
    };
  };

  # Local command index, fed by the pre-built database from
  # nix-index-database (flake input, wired in lib/default.nix). `comma`
  # gives a one-shot `, <cmd>` wrapper.
  programs.nix-index.enable                = true;
  programs.nix-index-database.comma.enable = true;

  programs.bash.enable = true;
}
