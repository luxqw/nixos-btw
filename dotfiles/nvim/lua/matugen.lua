 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#212226',
    base01 = '#2c2e33',
    base02 = '#35383e',
    base03 = '#6b6b71',
    base04 = '#e1e2e5',
    base05 = '#e1e2e5',
    base06 = '#e1e2e5',
    base07 = '#e1e2e5',
    base08 = '#debfbf',
    base09 = '#cecfeb',
    base0A = '#bfc0de',
    base0B = '#bfc0de',
    base0C = '#9699e9',
    base0D = '#9698e9',
    base0E = '#9698e9',
    base0F = '#bec0f4',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#e1e2e5',          bg = '#212226' })
  hi('TelescopeBorder',         { fg = '#6b6b71',             bg = '#212226' })
  hi('TelescopePromptNormal',   { fg = '#e1e2e5',          bg = '#212226' })
  hi('TelescopePromptBorder',   { fg = '#6b6b71',             bg = '#212226' })
  hi('TelescopePromptPrefix',   { fg = '#bfc0de',             bg = '#212226' })
  hi('TelescopePromptCounter',  { fg = '#e1e2e5',  bg = '#212226' })
  hi('TelescopePromptTitle',    { fg = '#212226',             bg = '#bfc0de' })
  hi('TelescopePreviewTitle',   { fg = '#212226',             bg = '#bfc0de' })
  hi('TelescopeResultsTitle',   { fg = '#212226',             bg = '#cecfeb' })
  hi('TelescopeSelection',      { fg = '#e1e2e5',          bg = '#35383e' })
  hi('TelescopeSelectionCaret', { fg = '#bfc0de',             bg = '#35383e' })
  hi('TelescopeMatching',       { fg = '#bfc0de',             bold = true })

  -- mini.pick
  hi('MiniPickNormal',         { fg = '#e1e2e5',          bg = '#212226' })
  hi('MiniPickBorder',         { fg = '#6b6b71',             bg = '#212226' })
  hi('MiniPickPrompt',   { fg = '#e1e2e5',          bg = '#212226' })
  hi('MiniPickPromptPrefix',   { fg = '#bfc0de',             bg = '#212226' })
  hi('MiniPickBorderText',    { fg = '#212226',             bg = '#bfc0de' })
  hi('MiniPickMatchCurrent',      { fg = '#e1e2e5',          bg = '#35383e' })
  hi('MiniPickPromptCaret', { fg = '#bfc0de',             bg = '#35383e' })
  hi('MiniPickMatchRanges',       { fg = '#bfc0de',             bold = true })
end

-- Register a signal handler for SIGUSR1 (matugen updates).
-- The handler re-requires this module, which re-runs the code below, so the
-- previous handle is stopped first; otherwise handlers double on every signal.
if _G.__matugen_signal then
  _G.__matugen_signal:stop()
  _G.__matugen_signal:close()
end

local signal = vim.uv.new_signal()
_G.__matugen_signal = signal
signal:start(
  'sigusr1',
  vim.schedule_wrap(function()
    package.loaded['matugen'] = nil
    require('matugen').setup()
  end)
)

return M
