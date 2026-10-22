# The neovim config starts over from kickstart.nvim

**Superseded by [0005](0005-neovim-config-is-lazyvim.md).**

The previous `dotfiles/nvim` was borrowed from someone else: a hand-rolled plugin manager, custom treesitter queries for nine languages, harpoon, fugitive and a set of home-grown `tony*` plugins. It worked, but its owner could not use it — there was no way to learn vim from a config whose every keybind was someone else's habit.

It is replaced by [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) (the `vim.pack` edition): one `init.lua` meant to be read top to bottom, with stock vim motions and a which-key popup for discovery. hardtime.nvim runs in hint mode, so bad habits get named but nothing is blocked. The old config survives only in git history.

Two things were carried over because they are about this machine, not about taste: `lua/matugen.lua` (noctalia regenerates it from the wallpaper) and vim-oscyank (copy to the local clipboard over ssh).

## Considered Options

- **Keep the old config, prune it** — rejected: what is left is still someone else's layout, and nothing explains it.
- **A distribution (LazyVim, NvChad)** — rejected: they hide the config behind their own abstractions, which is the opposite of learning.
- **nixvim / home-manager `programs.neovim` plugins** — rejected for now: every keymap tweak becomes a rebuild, and the lua that kickstart teaches gets wrapped in nix. The config stays a raw dotfile (see `docs/rationale.md`, editor).

## Consequences

Plugins are pulled from GitHub by `vim.pack` on first start and pinned by `nvim-pack-lock.json`, which is committed. Everything that is a binary — LSP servers, formatters, treesitter parsers and nvim-treesitter itself — comes from Nix instead.
