-- noctalia's neovim template regenerates lua/matugen.lua from the wallpaper
-- and paints it with base16-nvim; tokyonight is the fallback.
return {
  { "RRethy/base16-nvim", lazy = false, priority = 1000 },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        local ok, matugen = pcall(require, "matugen")
        if not (ok and pcall(matugen.setup)) then
          vim.cmd.colorscheme("tokyonight-night")
        end
      end,
    },
  },
}
