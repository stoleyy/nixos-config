{ pkgs, lib, ... }:

let
  proxyScript = pkgs.writeTextFile {
    name = "claude-openai-proxy";
    executable = true;
    destination = "/bin/claude-openai-proxy";
    text = ''
      #!${pkgs.python311}/bin/python3
      """
      Minimal OpenAI-compatible proxy for the claude CLI.
      Stdlib-only — no fastapi/uvicorn/pydantic dependencies.
      Listens on 127.0.0.1:8765. Accepts POST /v1/chat/completions,
      calls `claude -p` with the conversation, returns OpenAI-format JSON.
      Streaming is emulated by chunking the completed response as SSE.
      """
      import json
      import subprocess
      import threading
      import time
      import uuid
      from http.server import BaseHTTPRequestHandler, HTTPServer

      CLAUDE = "${pkgs.claude-code}/bin/claude"


      def run_claude(messages):
          parts = []
          for m in messages:
              role = m.get("role", "")
              content = m.get("content", "")
              if role == "system":
                  parts.append(f"[System]: {content}")
              elif role == "user":
                  parts.append(content)
              elif role == "assistant":
                  parts.append(f"[Assistant]: {content}")
          prompt = "\n\n".join(parts)
          try:
              r = subprocess.run(
                  [CLAUDE, "-p", prompt],
                  capture_output=True, text=True, timeout=180,
              )
              return r.stdout.strip() if r.returncode == 0 else f"Error: {r.stderr.strip()}"
          except subprocess.TimeoutExpired:
              return "Error: claude timed out"


      class ProxyHandler(BaseHTTPRequestHandler):
          def log_message(self, format, *args):
              pass

          def send_json(self, status, data):
              body = json.dumps(data).encode()
              self.send_response(status)
              self.send_header("Content-Type", "application/json")
              self.send_header("Content-Length", str(len(body)))
              self.end_headers()
              self.wfile.write(body)

          def do_GET(self):
              if self.path == "/v1/models":
                  self.send_json(200, {
                      "object": "list",
                      "data": [{"id": "claude", "object": "model", "created": 1700000000, "owned_by": "anthropic"}],
                  })
              else:
                  self.send_json(404, {"error": "not found"})

          def do_POST(self):
              if self.path != "/v1/chat/completions":
                  self.send_json(404, {"error": "not found"})
                  return
              length = int(self.headers.get("Content-Length", 0))
              try:
                  req = json.loads(self.rfile.read(length))
              except (json.JSONDecodeError, ValueError):
                  self.send_json(400, {"error": "bad json"})
                  return
              messages = req.get("messages", [])
              model = req.get("model", "claude")
              stream = req.get("stream", False)
              content = run_claude(messages)
              cid = f"chatcmpl-{uuid.uuid4().hex[:8]}"
              ts = int(time.time())
              if stream:
                  self.send_response(200)
                  self.send_header("Content-Type", "text/event-stream")
                  self.send_header("Cache-Control", "no-cache")
                  self.send_header("X-Accel-Buffering", "no")
                  self.end_headers()
                  for i in range(0, len(content), 30):
                      chunk = json.dumps({
                          "id": cid, "object": "chat.completion.chunk",
                          "created": ts, "model": model,
                          "choices": [{"index": 0, "delta": {"content": content[i:i+30]}, "finish_reason": None}],
                      })
                      self.wfile.write(f"data: {chunk}\n\n".encode())
                  done = json.dumps({
                      "id": cid, "object": "chat.completion.chunk",
                      "created": ts, "model": model,
                      "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                  })
                  self.wfile.write(f"data: {done}\n\ndata: [DONE]\n\n".encode())
              else:
                  self.send_json(200, {
                      "id": cid, "object": "chat.completion",
                      "created": ts, "model": model,
                      "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
                      "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
                  })


      class ThreadedHTTPServer(HTTPServer):
          """Handle each request in its own thread so claude calls don't block."""
          def process_request(self, request, client_address):
              t = threading.Thread(target=self._handle, args=(request, client_address))
              t.daemon = True
              t.start()

          def _handle(self, request, client_address):
              try:
                  self.finish_request(request, client_address)
              except Exception:
                  self.handle_error(request, client_address)
              finally:
                  self.shutdown_request(request)


      if __name__ == "__main__":
          server = ThreadedHTTPServer(("127.0.0.1", 8765), ProxyHandler)
          server.serve_forever()
    '';
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
      ExecStart = "${proxyScript}/bin/claude-openai-proxy";
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
