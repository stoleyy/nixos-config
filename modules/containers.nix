{ pkgs, ... }:

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
    };
    oci-containers.backend = "podman";
  };

  # Make podman-compose available for ad-hoc compose-file workloads.
  environment.systemPackages = with pkgs; [
    podman-compose
  ];
}
