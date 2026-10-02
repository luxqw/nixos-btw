-- hardtime.nvim nudges you off bad habits (jjjj, arrow keys, ...) with hints.
-- Hint mode only: nothing is blocked, you just get told a better motion.
-- :Hardtime report   shows which habits you repeat most.
-- :Hardtime disable  turns it off for the session.
vim.pack.add {
  'https://github.com/MunifTanjim/nui.nvim',
  'https://github.com/m4xshen/hardtime.nvim',
}

require('hardtime').setup {
  restriction_mode = 'hint',
  disable_mouse = false,
  disabled_keys = {
    ['<Up>'] = {},
    ['<Down>'] = {},
    ['<Left>'] = {},
    ['<Right>'] = {},
  },
}
