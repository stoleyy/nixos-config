{ pkgs, lib, ... }:

let
  python = pkgs.python311.withPackages (
    ps: with ps; [
      fastapi
      uvicorn
      pydantic
    ]
  );

  proxyScript = pkgs.writeTextFile {
    name = "claude-openai-proxy";
    executable = true;
    destination = "/bin/claude-openai-proxy";
    text = ''
      #!${python}/bin/python3
      """
      OpenAI-compatible proxy for the claude CLI.
      Listens on 127.0.0.1:8765. Accepts POST /v1/chat/completions,
      calls `claude -p` with the conversation, returns OpenAI-format JSON.
      Streaming is emulated by chunking the completed response as SSE.
      """
      import asyncio, json, subprocess, time, uuid
      from typing import AsyncIterator, Optional

      import uvicorn
      from fastapi import FastAPI
      from fastapi.responses import StreamingResponse
      from pydantic import BaseModel

      app = FastAPI()
      CLAUDE = "${pkgs.claude-code}/bin/claude"

      class Message(BaseModel):
          role: str
          content: str

      class ChatRequest(BaseModel):
          model: str = "claude"
          messages: list[Message]
          stream: bool = False
          temperature: Optional[float] = None
          max_tokens: Optional[int] = None

      def build_prompt(messages: list[Message]) -> str:
          parts = []
          for m in messages:
              if m.role == "system":
                  parts.append(f"[System]: {m.content}")
              elif m.role == "user":
                  parts.append(m.content)
              elif m.role == "assistant":
                  parts.append(f"[Assistant]: {m.content}")
          return "\n\n".join(parts)

      def _run_claude(prompt: str) -> str:
          r = subprocess.run(
              [CLAUDE, "-p", prompt],
              capture_output=True, text=True, timeout=180,
          )
          return r.stdout.strip() if r.returncode == 0 else f"Error: {r.stderr.strip()}"

      async def call_claude(prompt: str) -> str:
          loop = asyncio.get_event_loop()
          return await loop.run_in_executor(None, _run_claude, prompt)

      async def sse_stream(content: str, model: str) -> AsyncIterator[str]:
          cid = f"chatcmpl-{uuid.uuid4().hex[:8]}"
          ts = int(time.time())
          for i in range(0, len(content), 30):
              yield f"data: {json.dumps({'id':cid,'object':'chat.completion.chunk','created':ts,'model':model,'choices':[{'index':0,'delta':{'content':content[i:i+30]},'finish_reason':None}]})}\n\n"
              await asyncio.sleep(0)
          yield f"data: {json.dumps({'id':cid,'object':'chat.completion.chunk','created':ts,'model':model,'choices':[{'index':0,'delta':{},'finish_reason':'stop'}]})}\n\ndata: [DONE]\n\n"

      @app.post("/v1/chat/completions")
      async def chat_completions(req: ChatRequest):
          content = await call_claude(build_prompt(req.messages))
          if req.stream:
              return StreamingResponse(
                  sse_stream(content, req.model),
                  media_type="text/event-stream",
                  headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
              )
          return {
              "id": f"chatcmpl-{uuid.uuid4().hex[:8]}",
              "object": "chat.completion",
              "created": int(time.time()),
              "model": req.model,
              "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
              "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
          }

      @app.get("/v1/models")
      async def list_models():
          return {"object": "list", "data": [
              {"id": "claude", "object": "model", "created": 1700000000, "owned_by": "anthropic"}
          ]}

      if __name__ == "__main__":
          uvicorn.run(app, host="127.0.0.1", port=8765, log_level="warning")
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
