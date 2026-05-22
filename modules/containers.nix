{ pkgs, lib, ... }:

# Container runtime for declarative services (Wazuh manager, future workloads).
# Uses podman with dockerCompat = true so `virtualisation.oci-containers` works
# without pulling in the full Docker daemon. Rootful by design — easier to
# manage privileged ports (1514/1515/443) than rootless port-forwarding.
{
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true; # `docker` CLI = podman
      defaultNetwork.settings.dns_enabled = true; # container hostnames resolve
      autoPrune = {
        enable = true;
        dates = "weekly";
        # --all removed: pruning all unused images weekly would require re-pulling
        # large images (Wazuh ~1 GB) every week. Default (dangling only) is sufficient.
      };
    };
    oci-containers.backend = "podman";
  };

  # Restrict unqualified image pulls to trusted registries only.
  # mkForce: the containers module also writes this file; override it.
  environment.etc."containers/registries.conf".text = lib.mkForce ''
    unqualified-search-registries = ["docker.io", "ghcr.io", "quay.io"]
  '';

  # Make podman-compose available for ad-hoc compose-file workloads.
  environment.systemPackages = with pkgs; [
    podman-compose
  ];
}
