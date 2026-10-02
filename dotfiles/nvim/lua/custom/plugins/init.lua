-- Loads every other .lua file in this directory. Order is unspecified:
-- plugins that depend on each other belong in the same file.
local dir = vim.fs.joinpath(vim.fn.stdpath 'config', 'lua', 'custom', 'plugins')
for name, type in vim.fs.dir(dir, { follow = true }) do
  if (type == 'file' or type == 'link') and name:match '%.lua$' and name ~= 'init.lua' then
    require('custom.plugins.' .. name:gsub('%.lua$', ''))
  end
end
