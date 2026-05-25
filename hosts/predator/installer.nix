# Custom installer ISO — bakes in SSH key, sops age key, and network access
# for disaster recovery. Build with:
#   nix build .#installer
#
# Boot the ISO, then:
#   1. nix run github:nix-community/disko -- --mode destroy,format,mount ./hosts/predator/disko.nix
#   2. nixos-install --flake .#predator
#   3. Reboot
{
  pkgs,
  modulesPath,
  lib,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # Network access for fetching the flake during install.
  networking = {
    networkmanager.enable = true;
    wireless.enable = lib.mkForce false;
  };

  # Bake in essential tools for the install process.
  environment.systemPackages = with pkgs; [
    git
    vim
    sops
    ssh-to-age
    parted
    gptfdisk
  ];

  # Autologin as root — this is an installer, not a daily driver.
  users.users.root.initialHashedPassword = "";

  # Enable SSH so we can install remotely if needed.
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Bake stoleyy's SSH pubkey for passwordless remote install.
  users.users.root.openssh.authorizedKeys.keys = [
    # Replace with your actual SSH public key:
    # "ssh-ed25519 AAAA... stoleyy@predator"
  ];

  system.stateVersion = "25.11";
}
