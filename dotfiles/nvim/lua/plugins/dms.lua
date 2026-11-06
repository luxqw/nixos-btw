-- DMS paints nvim: its neovim template (matugenTemplateNeovim, switched on in
-- home.nix) writes colors/dms.lua and lua/lualine/themes/dms.lua here
-- (gitignored) on every colour change, and base46 does the painting.
-- tokyonight is the fallback until DMS has written them or while base46 is
-- missing: dms.lua then returns quietly without setting colors_name.
return {
  { "duxlabs-dev/base46", branch = "v3.0", lazy = false, priority = 1000 },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        if not (pcall(vim.cmd.colorscheme, "dms") and vim.g.colors_name == "dms") then
          vim.cmd.colorscheme("tokyonight-night")
        end
      end,
    },
  },
}
