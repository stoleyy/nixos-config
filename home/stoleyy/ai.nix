{ pkgs, ... }:

{
  home.packages = [ pkgs.aichat ];

  # aichat config — Ollama only, no API keys, no cloud providers.
  # World-readable (Nix store); safe because the only "secret" is the dummy
  # value that Ollama itself ignores.
  xdg.configFile."aichat/config.yaml".text = ''
    model: ollama:llama3.2
    stream: true
    save: true
    keybindings: emacs
    wrap: auto
    function_calling: true

    clients:
      - type: openai-compatible
        name: ollama
        api_base: http://localhost:11434/v1
        api_key: "ollama"
        models:
          - name: llama3.2
            max_input_tokens: 131072
            supports_function_calling: true
          - name: qwen2.5-coder:7b
            max_input_tokens: 32768
            supports_function_calling: true
  '';

  programs.fish.functions = {
    # Pipe a nix eval/build error to Claude for triage.
    # Usage:  nix flake check --no-build 2>&1 | nixfix
    #         nh os switch 2>&1 | nixfix
    nixfix = {
      description = "Analyse a nix eval/build error with Claude";
      body = ''
        set input (cat)
        if test -z "$input"
          echo "nixfix: pipe a nix error into this function"
          echo "  e.g.  nix flake check --no-build 2>&1 | nixfix"
          return 1
        end
        claude -p "You are a NixOS 25.11 expert. Analyse this error, explain \
        the root cause in one paragraph, then give the minimal precise fix \
        using exact NixOS option paths. Do not suggest changes outside the \
        error scope.\n\nError output:\n$input"
      '';
    };

    # Fetch recent journal logs for a unit and send them to Claude.
    # Usage:  sysfix ollama
    #         sysfix wg-quick-protonvpn
    sysfix = {
      description = "Analyse a failed systemd unit with Claude";
      body = ''
        if test (count $argv) -eq 0
          echo "Usage: sysfix <unit-name>"
          return 1
        end
        set logs (journalctl -u $argv[1] -b 0 --no-pager -n 200 2>&1)
        claude -p "You are a Linux/NixOS expert. These are systemd journal \
        logs for unit '$argv[1]' on NixOS 25.11. State what went wrong and \
        give the concrete fix, with exact NixOS option paths where relevant.\
        \n\nJournal:\n$logs"
      '';
    };

    # Ask a NixOS config question; the local flake context is injected.
    # Usage:  nixhelp "how do I enable bluetooth auto-connect"
    nixhelp = {
      description = "Ask a NixOS config question with flake context";
      body = ''
        if test (count $argv) -eq 0
          echo "Usage: nixhelp \"your question\""
          return 1
        end
        set flake (cat /etc/nixos/flake.nix 2>/dev/null)
        set mods (ls /etc/nixos/modules/ 2>/dev/null | string join ", ")
        claude -p "NixOS 25.11 config context:\n\nflake.nix:\n$flake\n\n\
        Modules present: $mods\n\nQuestion: $argv[1]"
      '';
    };

    # Open an interactive Claude agent session rooted at /etc/nixos so the
    # full harness is active: .mcp.json (mcp-nixos), .claude/hooks/, and
    # .claude/settings.json are all picked up automatically by Claude Code.
    # Usage:  agent
    #         agent --allowedTools Bash,Read,Write
    agent = {
      description = "Interactive Claude session with nixos-config harness";
      body = ''
        set _prev $PWD
        cd /etc/nixos
        claude $argv
        cd $_prev
      '';
    };

    # Local Ollama query — offline fallback, no auth required.
    # Usage:  localai "explain what services.ollama.acceleration does"
    #         localai -m ollama:qwen2.5-coder:7b "review this nix snippet"
    localai = {
      description = "Local Ollama AI (offline fallback via aichat)";
      body = "aichat $argv";
    };
  };
}
