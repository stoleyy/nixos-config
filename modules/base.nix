{ pkgs, ... }:

{
  users.users.stoleyy = {
    isNormalUser = true;
    description = "stoleyy";
    shell = pkgs.fish;
    # On Wayland + systemd-logind, per-seat ACLs grant active sessions
    # /dev/input/event* access automatically — no "input" group needed.
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "plugdev"
      "gamemode"
    ];
    packages = with pkgs; [ kdePackages.kate ];
  };

  environment.shells = with pkgs; [
    fish
    bash
  ];
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    chipsec
  ];
}
