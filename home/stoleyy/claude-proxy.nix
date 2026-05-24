{ pkgs, lib, ... }:

let
  proxyScript = pkgs.replaceVars ../../scripts/claude-openai-proxy.py {
    claude = "${pkgs.claude-code}/bin/claude";
  };
in
{
  # Proxy service — runs as stoleyy so it shares the claude auth session.
  systemd.user.services.claude-openai-proxy = {
    Unit = {
      Description = "OpenAI-compatible proxy for claude CLI";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.python311}/bin/python3 ${proxyScript}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Ensure ~/.local/bin is in fish PATH so `hermes` is found after uv install.
  programs.fish.shellInit = ''
    fish_add_path --move --prepend "$HOME/.local/bin"
  '';

  # Install hermes and write config as mutable files via activation.
  # home.file would create read-only Nix store symlinks — hermes needs to write
  # to config.yaml and .env at runtime, so we write plain files instead.
  home.activation.setupHermes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Write hermes config (mutable — hermes updates it at runtime)
    mkdir -p "$HOME/.hermes"

    if ! test -f "$HOME/.hermes/config.yaml"; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 /dev/stdin "$HOME/.hermes/config.yaml" << 'YAML'
    model:
      provider: custom
      model: claude
      base_url: http://127.0.0.1:8765/v1
    YAML
    fi

    if ! test -f "$HOME/.hermes/.env"; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 /dev/stdin "$HOME/.hermes/.env" << 'ENV'
    OPENAI_API_KEY=claude-cli-proxy
    ENV
    fi

    # Install hermes if not already present (needs network / VPN up)
    if ! test -x "$HOME/.local/bin/hermes"; then
      echo "Installing hermes-agent via uv..."
      $DRY_RUN_CMD ${pkgs.uv}/bin/uv tool install \
        "hermes-agent[all] @ git+https://github.com/NousResearch/hermes-agent.git" \
        --python ${pkgs.python311}/bin/python3 2>&1 \
        || echo "[warn] hermes install failed — run manually: uv tool install 'hermes-agent[all]'"
    fi
  '';

  programs.fish.functions.hermes-proxy-status = {
    description = "Check claude-openai-proxy systemd service";
    body = "systemctl --user status claude-openai-proxy";
  };
}
