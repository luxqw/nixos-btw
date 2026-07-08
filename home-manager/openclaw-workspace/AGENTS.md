# AGENTS.md — OpenClaw Workspace

This file is managed by Nix. Update it in the repo, not in the workspace.

Principles
- Be concise in chat; write long output to files.
- Treat this workspace as the system of record.
- Prefer explicit, deterministic changes.
- NEVER send any message (iMessage, email, SMS, etc.) without explicit user confirmation:
  - Always show the full message text and ask: “I’m going to send this: <message>. Send? (y/n)”

Tool disambiguation
- `write` — write a file on THIS machine (local workspace/filesystem). Params: `path`, `content`. Use this for normal file writes.
- `file_write` — write bytes to a DIFFERENT paired node (phone, remote device), never local. Params: `node`, `path`, `contentBase64` (not `content`). Requires operator-configured transfer policy; will fail without it.
- If a local file write fails validation on `file_write` (e.g. missing `node`), retry with `write` instead.
