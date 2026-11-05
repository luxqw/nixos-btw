-- Caelestia user template: ~/.local/state/caelestia/theme/nvim.lua, reached
-- through session-theme/nvim.lua (Hyprland only; plugins/base16.lua loads it).
-- Port of Noctalia's neovim template, painted with base16-nvim.
local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#{{ surface.hex }}',
    base01 = '#{{ surfaceContainer.hex }}',
    base02 = '#{{ surfaceContainerHigh.hex }}',
    base03 = '#{{ outline.hex }}',
    base04 = '#{{ onSurfaceVariant.hex }}',
    base05 = '#{{ onSurface.hex }}',
    base06 = '#{{ onSurface.hex }}',
    base07 = '#{{ onBackground.hex }}',
    base08 = '#{{ error.hex }}',
    base09 = '#{{ tertiary.hex }}',
    base0A = '#{{ secondary.hex }}',
    base0B = '#{{ primary.hex }}',
    base0C = '#{{ tertiaryFixedDim.hex }}',
    base0D = '#{{ primaryFixedDim.hex }}',
    base0E = '#{{ secondaryFixedDim.hex }}',
    base0F = '#{{ secondaryFixed.hex }}',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#{{ onSurface.hex }}',         bg = '#{{ surface.hex }}' })
  hi('TelescopeBorder',         { fg = '#{{ outline.hex }}',           bg = '#{{ surface.hex }}' })
  hi('TelescopePromptNormal',   { fg = '#{{ onSurface.hex }}',         bg = '#{{ surface.hex }}' })
  hi('TelescopePromptBorder',   { fg = '#{{ outline.hex }}',           bg = '#{{ surface.hex }}' })
  hi('TelescopePromptPrefix',   { fg = '#{{ primary.hex }}',           bg = '#{{ surface.hex }}' })
  hi('TelescopePromptCounter',  { fg = '#{{ onSurfaceVariant.hex }}',  bg = '#{{ surface.hex }}' })
  hi('TelescopePromptTitle',    { fg = '#{{ surface.hex }}',           bg = '#{{ primary.hex }}' })
  hi('TelescopePreviewTitle',   { fg = '#{{ surface.hex }}',           bg = '#{{ secondary.hex }}' })
  hi('TelescopeResultsTitle',   { fg = '#{{ surface.hex }}',           bg = '#{{ tertiary.hex }}' })
  hi('TelescopeSelection',      { fg = '#{{ onSurface.hex }}',         bg = '#{{ surfaceContainerHigh.hex }}' })
  hi('TelescopeSelectionCaret', { fg = '#{{ primary.hex }}',           bg = '#{{ surfaceContainerHigh.hex }}' })
  hi('TelescopeMatching',       { fg = '#{{ primary.hex }}',           bold = true })

  -- mini.pick
  hi('MiniPickNormal',        { fg = '#{{ onSurface.hex }}', bg = '#{{ surface.hex }}' })
  hi('MiniPickBorder',        { fg = '#{{ outline.hex }}',   bg = '#{{ surface.hex }}' })
  hi('MiniPickPrompt',        { fg = '#{{ onSurface.hex }}', bg = '#{{ surface.hex }}' })
  hi('MiniPickPromptPrefix',  { fg = '#{{ primary.hex }}',   bg = '#{{ surface.hex }}' })
  hi('MiniPickBorderText',    { fg = '#{{ surface.hex }}',   bg = '#{{ primary.hex }}' })
  hi('MiniPickMatchCurrent',  { fg = '#{{ onSurface.hex }}', bg = '#{{ surfaceContainerHigh.hex }}' })
  hi('MiniPickPromptCaret',   { fg = '#{{ primary.hex }}',   bg = '#{{ surfaceContainerHigh.hex }}' })
  hi('MiniPickMatchRanges',   { fg = '#{{ primary.hex }}',   bold = true })
end

return M
