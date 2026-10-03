-- lazygit in a floating window over the current repo.
--   <leader>gg   open lazygit (q closes it)
-- lazygit itself comes from Nix (programs.lazygit in home.nix).
vim.pack.add {
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/kdheepak/lazygit.nvim',
}

vim.keymap.set('n', '<leader>gg', '<cmd>LazyGit<CR>', { desc = '[G]it: lazy[g]it' })
