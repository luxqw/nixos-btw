{inputs, ...}: {
  imports = [inputs.nix-openclaw.homeManagerModules.openclaw];

  programs.openclaw = {
    enable = true;

    workspace.bootstrapFiles = {
      agents = ../openclaw-workspace/AGENTS.md;
      soul = ../openclaw-workspace/SOUL.md;
      tools = ../openclaw-workspace/TOOLS.md;
      identity = ../openclaw-workspace/IDENTITY.md;
      user = ../openclaw-workspace/USER.md;
    };

    environment.OPENCLAW_GATEWAY_TOKEN = "/etc/nixos/secrets/openclaw-gateway-token";

    config = {
      gateway = {
        mode = "local";
        auth.token = {
          source = "env";
          provider = "default";
          id = "OPENCLAW_GATEWAY_TOKEN";
        };
      };

      channels.telegram = {
        tokenFile = "/etc/nixos/secrets/telegram-bot-token";
        allowFrom = [543259508];
        groups."*".requireMention = true;
      };

      # Local Ollama models — no API key needed, runs entirely on this machine.
      # Back on native api = "ollama" (openai-completions against Ollama's
      # /v1 shim was tried to fix tool-calling reliability but hit its own
      # schema errors on multi-turn tool replies — not clearly better, not
      # worth the added complexity). Tool-calling reliability with these
      # local models remains inconsistent either way; accepted as a known
      # limitation for now. Context-window fix (OLLAMA_CONTEXT_LENGTH in
      # nixos/modules/ollama.nix) is independent of this and still applies.
      models.providers.ollama = {
        api = "ollama";
        baseUrl = "http://127.0.0.1:11434";
        models = [
          {
            id = "gemma4:latest";
            name = "Gemma4";
            maxTokens = 64000;
          }
        ];
      };

      agents.defaults = {
        model = "ollama/gemma4:latest";
        reasoningDefault = "on";
      };

      memory.backend = "qmd";
    };
  };

  # The nix-openclaw module ships a bare [Unit]/[Service] with no
  # [Install] section, so it can't be enabled via systemctl. Add
  # WantedBy ourselves so the gateway starts on login (and, combined
  # with lingering for this user, on boot too).
  systemd.user.services.openclaw-gateway.Install.WantedBy = ["default.target"];
}
