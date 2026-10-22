-- Binaries come from Nix (home.nix), so Mason is off and nothing here
-- downloads a server or compiles a parser.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "iamcco/markdown-preview.nvim", enabled = false },

  {
    "nvim-treesitter/nvim-treesitter",
    dir = vim.fn.stdpath("data") .. "/nix/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = { enabled = false },
        nixd = {},
      },
    },
  },

  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        nix = { "alejandra" },
      },
    },
  },
}
