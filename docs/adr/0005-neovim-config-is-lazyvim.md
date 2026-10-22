# The neovim config is LazyVim

Supersedes [0003](0003-neovim-config-from-kickstart.md).

Kickstart was chosen so the config could be read top to bottom and learned from. In practice nvim stayed the second editor: Zed opens code files, and a hand-grown kickstart never reached the point where it felt finished. The owner asked for LazyVim by name — the same reason lazygit is liked: sensible defaults and documented keys that someone else maintains.

`dotfiles/nvim` is now the LazyVim starter layout: `init.lua` loads `lua/config/lazy.lua`, which imports LazyVim, the language extras (go, json, markdown, nix, yaml) and our own specs from `lua/plugins/`. Plugins are fetched by lazy.nvim and pinned by the committed `lazy-lock.json`.

What did not change is the Nix boundary from 0003. Every binary — LSP servers, formatters, linters, treesitter parsers and nvim-treesitter itself — comes from `home.nix`, so `lua/plugins/nix.lua` turns Mason off, points the nvim-treesitter spec at the Nix copy and empties `ensure_installed`. The lang extras pick `nil_ls` and `nixfmt`; that file swaps them for `nixd` and `alejandra`. Colors still come from noctalia's `lua/matugen.lua` through base16-nvim. vim-oscyank is gone: nvim's built-in OSC 52 provider covers copying over ssh. hardtime.nvim stays in hint mode.

## Considered Options

- **Keep kickstart** — rejected: it was not getting used.
- **LazyVim as a second `NVIM_APPNAME`** — rejected: two configs to keep working for one editor.
- **nixvim with the LazyVim preset** — rejected for the same reason as in 0003: every keymap tweak becomes a rebuild.

## Consequences

The first start needs network to clone plugins. `:Lazy update` moves the pins and changes `lazy-lock.json`, which is committed like `flake.lock`. A new language is an extra import in `lua/config/lazy.lua` plus its binaries and grammar in `home.nix`; a missing binary shows up as an `ENOENT` from nvim-lint or a server that never attaches.
