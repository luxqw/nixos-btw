{pkgs, ...}: {
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    # OpenClaw's system prompt (tool defs + workspace bootstrap files) blows
    # past Ollama's own 4096-token default context window, truncating
    # generation before a reply is produced. Raise the default here since
    # per-request num_ctx isn't reliably forwarded by the OpenClaw client.
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "64000";
    };
  };
}
