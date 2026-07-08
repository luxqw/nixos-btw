require("config.options")
require("config.keybinds")
require("manage").setup()

local ok, matugen = pcall(require, 'matugen')
if ok then matugen.setup() end
