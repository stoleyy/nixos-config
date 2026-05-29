# User account, shell, and foundational system settings — imports shell.nix implicitly via home-manager.
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
      # Membership is REQUIRED for `sg untrusted` to succeed (a non-member
      # cannot switch into a passwordless group). The LAN-isolated +
      # Tor-routed browser domains (home/stoleyy/browser.nix) launch via
      # `sg untrusted -c ...`; without this they silently fail to start.
      "untrusted"
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
    # chipsec: run on-demand via `nix shell nixpkgs#chipsec` (189 MiB closure savings)
  ];
}
