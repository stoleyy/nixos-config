_:

{
  services.ollama = {
    enable = true;
    acceleration = "cuda";
    host = "127.0.0.1";
    # Pulled asynchronously by the generated ollama-model-loader unit.
    # Soft-fail: rebuild does not block if registry.ollama.ai is unreachable.
    loadModels = [
      "llama3.2" # 3B / ~2 GB VRAM — fast local fallback
      "qwen2.5-coder:7b" # 7B / ~4.7 GB VRAM — code/Nix offline tasks
    ];
    # Release VRAM after 10 min idle so gaming workloads aren't impacted.
    environmentVariables.OLLAMA_KEEP_ALIVE = "10m";
  };

  # The ProtonVPN kill switch drops all non-tunnel outbound until wg-quick
  # establishes the interface. `wants` keeps this soft (loader still starts
  # if VPN is disabled); `after` gives the tunnel a chance to come up first
  # so model pulls succeed without kill-switch interference.
  # Verify the generated service name: systemctl list-units | grep ollama
  systemd.services.ollama-model-loader = {
    wants = [ "wg-quick-protonvpn.service" ];
    after = [ "wg-quick-protonvpn.service" ];
  };
}
