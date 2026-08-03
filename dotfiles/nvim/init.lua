require("config.options")
require("config.keybinds")
require("manage").setup()

local matugen_ok, matugen = pcall(require, 'matugen')
vim.g.matugen_active = matugen_ok and pcall(matugen.setup)
