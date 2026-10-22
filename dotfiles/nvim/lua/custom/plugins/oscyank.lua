-- Copy to the *local* clipboard from anywhere, including over ssh and inside
-- zellij, via the OSC 52 terminal escape. foot supports it.
--   <leader>y{motion}   e.g. <leader>yip copies a paragraph
--   <leader>y           in visual mode copies the selection
vim.pack.add { 'https://github.com/ojroques/vim-oscyank' }

vim.keymap.set('n', '<leader>y', '<Plug>OSCYankOperator', { desc = '[Y]ank to clipboard (OSC 52)' })
vim.keymap.set('v', '<leader>y', '<Plug>OSCYankVisual', { desc = '[Y]ank to clipboard (OSC 52)' })
