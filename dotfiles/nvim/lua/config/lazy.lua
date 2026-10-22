local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("cloning lazy.nvim failed:\n" .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "lazyvim.plugins.extras.lang.go" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.markdown" },
    { import = "lazyvim.plugins.extras.lang.nix" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  checker = { enabled = false },
  change_detection = { notify = false },
  performance = {
    rtp = {
      -- site/ holds the Nix treesitter parsers
      paths = { vim.fn.stdpath("data") .. "/site" },
      disabled_plugins = { "gzip", "tarPlugin", "tohtml", "zipPlugin" },
    },
  },
})
