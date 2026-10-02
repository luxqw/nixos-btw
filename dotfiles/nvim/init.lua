--[[
  Based on kickstart.nvim (https://github.com/nvim-lua/kickstart.nvim, vim.pack edition).

  Differences from upstream:
    - LSP servers, formatters and treesitter parsers come from Nix (home.nix),
      not from Mason / :TSInstall. Nothing here downloads a binary.
    - Colors come from noctalia's matugen template (lua/matugen.lua) and
      follow the wallpaper; tokyonight is the fallback.
    - Extras live in lua/custom/plugins/: vim-oscyank, hardtime.nvim.

  Cheat sheet: README.md next to this file. Start with `vimtutor` in a shell.
  Read this file top to bottom; `:help <word>` explains anything you don't know.
--]]

-- ============================================================
-- OPTIONS  (:help option-list)
-- ============================================================
do
  vim.loader.enable()

  -- <Space> is the leader key. Must be set before any mapping uses it.
  vim.g.mapleader = ' '
  vim.g.maplocalleader = ' '

  -- foot uses Iosevka Nerd Font.
  vim.g.have_nerd_font = true

  vim.o.number = true
  vim.o.relativenumber = true -- makes counts like 5j / 3k easy to read off
  vim.o.mouse = 'a'
  vim.o.showmode = false -- mode is already in the statusline

  -- Share the system clipboard (wl-clipboard). Scheduled: it can slow startup.
  -- Over ssh there is no Wayland, so use <leader>y (OSC 52) instead.
  vim.schedule(function() vim.o.clipboard = 'unnamedplus' end)

  vim.o.breakindent = true
  vim.o.undofile = true
  vim.o.ignorecase = true
  vim.o.smartcase = true
  vim.o.signcolumn = 'yes'
  vim.o.updatetime = 250
  vim.o.timeoutlen = 300
  vim.o.splitright = true
  vim.o.splitbelow = true
  vim.o.list = true
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
  vim.o.inccommand = 'split' -- live preview of :s/foo/bar/
  vim.o.cursorline = true
  vim.o.scrolloff = 10
  vim.o.confirm = true -- ask instead of failing on :q with unsaved changes
end

-- ============================================================
-- BASIC KEYMAPS  (:help vim.keymap.set)
-- ============================================================
do
  vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

  vim.diagnostic.config {
    update_in_insert = false,
    severity_sort = true,
    float = { border = 'rounded', source = 'if_many' },
    underline = { severity = { min = vim.diagnostic.severity.WARN } },
    virtual_text = true,
    jump = {
      on_jump = function(_, bufnr) vim.diagnostic.open_float { bufnr = bufnr, scope = 'cursor', focus = false } end,
    },
  }
  vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

  vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

  -- CTRL+hjkl moves between splits.
  vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
  vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
  vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
  vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

  vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight when yanking (copying) text',
    group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
    callback = function() vim.hl.on_yank() end,
  })
end

-- ============================================================
-- PLUGINS  (:help vim.pack)
--   :lua vim.pack.update()   update all plugins (review, then :write)
--   nvim-pack-lock.json      pins versions; commit it
-- ============================================================
local function gh(repo) return 'https://github.com/' .. repo end

vim.api.nvim_create_autocmd('PackChanged', {
  callback = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if (kind == 'install' or kind == 'update') and name == 'telescope-fzf-native.nvim' and vim.fn.executable 'make' == 1 then
      vim.system({ 'make' }, { cwd = ev.data.path }):wait()
    end
  end,
})

-- ============================================================
-- UI: colors, which-key, git signs, statusline
-- ============================================================
do
  -- Detect tabstop/shiftwidth from the file.
  vim.pack.add { gh 'NMAC427/guess-indent.nvim' }
  require('guess-indent').setup {}

  -- base16-nvim is what lua/matugen.lua paints with.
  vim.pack.add { gh 'folke/tokyonight.nvim', gh 'RRethy/base16-nvim' }
  require('tokyonight').setup { styles = { comments = { italic = false } } }
  local ok, matugen = pcall(require, 'matugen')
  if not (ok and pcall(matugen.setup)) then vim.cmd.colorscheme 'tokyonight-night' end

  -- which-key: press <Space> and wait — it shows what comes next.
  vim.pack.add { gh 'folke/which-key.nvim' }
  require('which-key').setup {
    delay = 0,
    icons = { mappings = vim.g.have_nerd_font },
    spec = {
      { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
      { '<leader>t', group = '[T]oggle' },
      { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
      { 'gr', group = 'LSP Actions', mode = { 'n' } },
    },
  }

  vim.pack.add { gh 'lewis6991/gitsigns.nvim' }
  local gitsigns = require 'gitsigns'
  gitsigns.setup {
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    on_attach = function(bufnr)
      local function map(mode, l, r, desc) vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc }) end
      map('n', ']c', function()
        if vim.wo.diff then
          vim.cmd.normal { ']c', bang = true }
        else
          gitsigns.nav_hunk 'next'
        end
      end, 'Jump to next git [c]hange')
      map('n', '[c', function()
        if vim.wo.diff then
          vim.cmd.normal { '[c', bang = true }
        else
          gitsigns.nav_hunk 'prev'
        end
      end, 'Jump to previous git [c]hange')
      map('v', '<leader>hs', function() gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' } end, 'git [s]tage hunk')
      map('v', '<leader>hr', function() gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' } end, 'git [r]eset hunk')
      map('n', '<leader>hs', gitsigns.stage_hunk, 'git [s]tage hunk')
      map('n', '<leader>hr', gitsigns.reset_hunk, 'git [r]eset hunk')
      map('n', '<leader>hS', gitsigns.stage_buffer, 'git [S]tage buffer')
      map('n', '<leader>hR', gitsigns.reset_buffer, 'git [R]eset buffer')
      map('n', '<leader>hp', gitsigns.preview_hunk, 'git [p]review hunk')
      map('n', '<leader>hb', function() gitsigns.blame_line { full = true } end, 'git [b]lame line')
      map('n', '<leader>hd', gitsigns.diffthis, 'git [d]iff against index')
      map('n', '<leader>tb', gitsigns.toggle_current_line_blame, '[T]oggle git show [b]lame line')
      map({ 'o', 'x' }, 'ih', gitsigns.select_hunk, 'text object [i]nside [h]unk')
    end,
  }

  vim.pack.add { gh 'folke/todo-comments.nvim' }
  require('todo-comments').setup { signs = false }

  -- mini.nvim: text objects (va), cia, ci"), surround (saiw), statusline.
  vim.pack.add { gh 'nvim-mini/mini.nvim' }
  if vim.g.have_nerd_font then
    require('mini.icons').setup()
    MiniIcons.mock_nvim_web_devicons()
  end
  require('mini.ai').setup { mappings = { around_next = 'aa', inside_next = 'ii' }, n_lines = 500 }
  require('mini.surround').setup()
  local statusline = require 'mini.statusline'
  statusline.setup { use_icons = vim.g.have_nerd_font }
  statusline.section_location = function() return '%2l:%-2v' end
end

-- ============================================================
-- TELESCOPE: fuzzy finder  (:help telescope)
-- ============================================================
do
  local telescope_plugins = {
    gh 'nvim-lua/plenary.nvim',
    gh 'nvim-telescope/telescope.nvim',
    gh 'nvim-telescope/telescope-ui-select.nvim',
  }
  if vim.fn.executable 'make' == 1 then table.insert(telescope_plugins, gh 'nvim-telescope/telescope-fzf-native.nvim') end
  vim.pack.add(telescope_plugins)

  require('telescope').setup {
    extensions = { ['ui-select'] = { require('telescope.themes').get_dropdown() } },
  }
  pcall(require('telescope').load_extension, 'fzf')
  pcall(require('telescope').load_extension, 'ui-select')

  local builtin = require 'telescope.builtin'
  vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
  vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
  vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
  vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
  vim.keymap.set({ 'n', 'v' }, '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
  vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
  vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
  vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
  vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files' })
  vim.keymap.set('n', '<leader>sc', builtin.commands, { desc = '[S]earch [C]ommands' })
  vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
  vim.keymap.set('n', '<leader>/', function()
    builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown { winblend = 10, previewer = false })
  end, { desc = '[/] Fuzzily search in current buffer' })
  vim.keymap.set('n', '<leader>sn', function() builtin.find_files { cwd = vim.fn.stdpath 'config', follow = true } end, { desc = '[S]earch [N]eovim files' })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('telescope-lsp-attach', { clear = true }),
    callback = function(event)
      local buf = event.buf
      vim.keymap.set('n', 'grr', builtin.lsp_references, { buffer = buf, desc = '[G]oto [R]eferences' })
      vim.keymap.set('n', 'gri', builtin.lsp_implementations, { buffer = buf, desc = '[G]oto [I]mplementation' })
      vim.keymap.set('n', 'grd', builtin.lsp_definitions, { buffer = buf, desc = '[G]oto [D]efinition' })
      vim.keymap.set('n', 'grt', builtin.lsp_type_definitions, { buffer = buf, desc = '[G]oto [T]ype Definition' })
      vim.keymap.set('n', 'gO', builtin.lsp_document_symbols, { buffer = buf, desc = 'Open Document Symbols' })
      vim.keymap.set('n', 'gW', builtin.lsp_dynamic_workspace_symbols, { buffer = buf, desc = 'Open Workspace Symbols' })
    end,
  })
end

-- ============================================================
-- LSP  (:help lsp)
--   Servers are installed by Nix (home.nix → dev); here we only enable them.
--   nvim-lspconfig supplies the default config for each server name.
-- ============================================================
do
  vim.pack.add { gh 'j-hui/fidget.nvim', gh 'neovim/nvim-lspconfig' }
  require('fidget').setup {}

  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
    callback = function(event)
      local map = function(keys, func, desc, mode)
        vim.keymap.set(mode or 'n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
      end
      map('grn', vim.lsp.buf.rename, '[R]e[n]ame')
      map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })
      map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client:supports_method('textDocument/documentHighlight', event.buf) then
        local group = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, { buffer = event.buf, group = group, callback = vim.lsp.buf.document_highlight })
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, { buffer = event.buf, group = group, callback = vim.lsp.buf.clear_references })
        vim.api.nvim_create_autocmd('LspDetach', {
          group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
          callback = function(event2)
            vim.lsp.buf.clear_references()
            vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
          end,
        })
      end
      if client and client:supports_method('textDocument/inlayHint', event.buf) then
        map('<leader>th', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, '[T]oggle Inlay [H]ints')
      end
    end,
  })

  local flake = '(builtins.getFlake "/etc/nixos")'

  ---@type table<string, vim.lsp.Config>
  local servers = {
    gopls = {
      settings = {
        gopls = {
          staticcheck = true,
          analyses = { unusedparams = true },
          hints = { parameterNames = true, assignVariableTypes = true },
        },
      },
    },

    nixd = {
      settings = {
        nixd = {
          formatting = { command = { 'alejandra' } },
          nixpkgs = { expr = 'import ' .. flake .. '.inputs.nixpkgs {}' },
          options = {
            nixos = { expr = flake .. '.nixosConfigurations.nixos.options' },
            home_manager = { expr = flake .. '.nixosConfigurations.nixos.options.home-manager.users.type.getSubOptions []' },
          },
        },
      },
    },

    lua_ls = {
      on_init = function(client)
        if client.workspace_folders then
          local path = client.workspace_folders[1].name
          if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then return end
        end
        client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
          runtime = { version = 'LuaJIT', path = { 'lua/?.lua', 'lua/?/init.lua' } },
          workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
        })
      end,
      settings = { Lua = { format = { enable = false } } }, -- stylua formats
    },

    jsonls = {},
    yamlls = {},
  }

  for name, server in pairs(servers) do
    vim.lsp.config(name, server)
    vim.lsp.enable(name)
  end
end

-- ============================================================
-- FORMATTING  (conform.nvim) — <leader>f, and on save for go/nix/lua
-- ============================================================
do
  vim.pack.add { gh 'stevearc/conform.nvim' }
  require('conform').setup {
    notify_on_error = false,
    format_on_save = function(bufnr)
      local enabled = { go = true, nix = true, lua = true }
      if enabled[vim.bo[bufnr].filetype] then return { timeout_ms = 500 } end
    end,
    default_format_opts = { lsp_format = 'fallback' },
    formatters_by_ft = {
      go = { 'goimports' }, -- gofmt + adds/removes imports
      nix = { 'alejandra' },
      lua = { 'stylua' },
    },
  }
  vim.keymap.set({ 'n', 'v' }, '<leader>f', function() require('conform').format { async = true } end, { desc = '[F]ormat buffer' })
end

-- ============================================================
-- COMPLETION  (blink.cmp)  — <C-y> accept, <C-n>/<C-p> select,
--   <C-space> docs, <C-e> close, <C-k> signature help
-- ============================================================
do
  vim.pack.add { { src = gh 'L3MON4D3/LuaSnip', version = vim.version.range '2.*' } }
  require('luasnip').setup {}

  vim.pack.add { { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' } }
  require('blink.cmp').setup {
    keymap = { preset = 'default' },
    appearance = { nerd_font_variant = 'mono' },
    completion = { documentation = { auto_show = false, auto_show_delay_ms = 500 } },
    sources = { default = { 'lsp', 'path', 'snippets' } },
    snippets = { preset = 'luasnip' },
    fuzzy = { implementation = 'lua' },
    signature = { enabled = true },
  }
end

-- ============================================================
-- TREESITTER  (:help treesitter)
--   nvim-treesitter, its queries and the parsers (go nix lua bash json yaml
--   markdown) are all installed by Nix into ~/.local/share/nvim/site, at
--   matching versions. Add a language in home.nix (nvimGrammars), not here.
-- ============================================================
do
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('kickstart-treesitter', { clear = true }),
    callback = function(args)
      local lang = vim.treesitter.language.get_lang(args.match)
      if not lang or not vim.treesitter.language.add(lang) then return end
      vim.treesitter.start(args.buf, lang)
      if vim.treesitter.query.get(lang, 'indents') then vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()" end
    end,
  })
end

-- ============================================================
-- YOUR OWN PLUGINS: every lua/custom/plugins/*.lua is loaded.
-- ============================================================
require 'custom.plugins'

-- vim: ts=2 sts=2 sw=2 et
