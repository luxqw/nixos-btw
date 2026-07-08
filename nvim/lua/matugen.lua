 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#121316',
    base01 = '#1f1f22',
    base02 = '#292a2d',
    base03 = '#8e9099',
    base04 = '#c4c6cf',
    base05 = '#e3e2e6',
    base06 = '#e3e2e6',
    base07 = '#e3e2e6',
    base08 = '#ffb4ab',
    base09 = '#e9b7e3',
    base0A = '#bfc6db',
    base0B = '#b1c6f6',
    base0C = '#e9b7e3',
    base0D = '#b1c6f6',
    base0E = '#bfc6db',
    base0F = '#93000a',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  hi('TelescopeNormal',         { fg = '#e3e2e6',          bg = '#121316' })
  hi('TelescopeBorder',         { fg = '#8e9099',             bg = '#121316' })
  hi('TelescopePromptNormal',   { fg = '#e3e2e6',          bg = '#121316' })
  hi('TelescopePromptBorder',   { fg = '#8e9099',             bg = '#121316' })
  hi('TelescopePromptPrefix',   { fg = '#b1c6f6',             bg = '#121316' })
  hi('TelescopePromptCounter',  { fg = '#c4c6cf',  bg = '#121316' })
  hi('TelescopePromptTitle',    { fg = '#121316',             bg = '#b1c6f6' })
  hi('TelescopePreviewTitle',   { fg = '#121316',             bg = '#bfc6db' })
  hi('TelescopeResultsTitle',   { fg = '#121316',             bg = '#e9b7e3' })
  hi('TelescopeSelection',      { fg = '#e3e2e6',          bg = '#292a2d' })
  hi('TelescopeSelectionCaret', { fg = '#b1c6f6',             bg = '#292a2d' })
  hi('TelescopeMatching',       { fg = '#b1c6f6',             bold = true })
end

 -- Register a signal handler for SIGUSR1 (matugen updates)
 local signal = vim.uv.new_signal()
 signal:start(
   'sigusr1',
   vim.schedule_wrap(function()
     package.loaded['matugen'] = nil
     require('matugen').setup()
   end)
 )

 return M
