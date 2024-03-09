# Starter luavim setup


1. Move all your old `./config/nvim` and `.vimrc` files to a backup.

1. Create: `~/.config/nvim/init.lua`

```lua

-- old vimrc: /home/.vimrc (gf to edit)

-- Contents: (* to jump)
-- - vimoptions
-- - vimkeybindings
-- - vimplugins
-- - vimcustom

-- vim crash course!
-- press i to enter insert mode, type text.
-- <Esc> to leave insert mode and go back to normal mode.
-- it's best to stay in normal mode most of the time.
-- in normal mode, use arrow keys or hjkl to move cursor.
-- :q<CR> to quit, :w<CR> to save, :x<CR> to save and quit.
-- open file: :e <filepath><CR>
-- next buffer: :bn<CR>, previous buffer: :bp<CR>
-- go to line: :<line number><CR>
-- start of file: gg, end of file: G
-- search: / (search forward), ? (search backward), n (next), N (previous)
-- replace: :s/old/new/g (replace all occurrences in line), :%s/old/new/g (replace all occurrences in file)
-- movements: w (word), b (back), % (matching bracket), { and } (paragraph)
-- delete: x (delete character), dd (delete line)
-- copy and paste: yy (yank line), p (paste after cursor), P (paste before cursor)
-- more ways to enter insert mode: a (append), A (append at end of line), I (insert at beginning of line),
--   o (open new line below), O (open new line above)
-- undo and redo: u (undo), <C-r> (redo)
-- delete text and enter insert mode: c<movement> (change ...) d<movement> (delete ...),
--   s (delete character and enter insert mode)
-- repeat last command: .

-- many more on vim cheat sheet:
-- https://devhints.io/vim (gx to open)

-- vimoptions (* to jump to index)
vim.opt.number = true -- show line numbers
vim.opt.confirm = true -- confirm before overwriting files
vim.opt.clipboard:append("unnamedplus") -- use system clipboard


-- vimkeybindings (* to jump to index)
-- The descriptions can be read by plugins like https://github.com/folke/which-key.nvim (gx to open)
vim.g.mapleader = " " -- set leader to space
vim.keymap.set('n', '<leader>vv', '<cmd>edit ~/.config/nvim/init.lua<cr>', { desc = 'edit init.lua' })
vim.keymap.set('n', '<leader>vt', '<cmd>edit ~/todo.md<cr>', { desc = 'edit todo.md' })
vim.keymap.set('n', '<leader>/', '<cmd>nohls<cr>', { desc = 'clear search highlight' })
vim.keymap.set('v', 'p', 'pgvy', { desc = "keep clipboard when pasting over selection" })
vim.keymap.set('n', 'Y', 'y$', { desc = 'yank till end of line. (Y behaves like D and C)' })
vim.keymap.set('n', "<leader>p", "v$<Left>pgvy", { desc = 'paste over rest of line' }) -- not P, pecause P is: paste before cursor
vim.keymap.set('v', '>', '>gv', { desc = ">, keep selection when indenting" })
vim.keymap.set('v', '<', '<gv', { desc = "<, keep selection when indenting" })
vim.keymap.set('n', 'h', "<cmd>let @/ = expand('<cword>')<cr>:set hls<cr>", { desc = 'highlight word under cursor' })

-- lua functions
vim.keymap.set('n', "<leader>n",
  function()
    local has_errors = next(vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })) ~= nil
    if has_errors then
      vim.diagnostic.goto_next { severity = vim.diagnostic.severity.ERROR, float = true }
    else
      local has_warnings = next(vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })) ~=
          nil
      if has_warnings then
        vim.diagnostic.goto_next { severity = vim.diagnostic.severity.WARN, float = true }
      else
        vim.diagnostic.goto_next { float = true }
      end
    end
  end,
  { desc = "Jump to next LSP diagnostic" }
)


-- vimplugins (* to jump to index)
-- plugin manager: lazy.nvim
-- https://github.com/folke/lazy.nvim (gx to open)
-- popular plugin manager as of 2024.
-- lazy.nvim loads plugins on demand for fast startup times.
-- plugins are loaded by events: vim-start, keybindings, filetypes, etc.
-- https://github.com/folke/lazy.nvim#lazy-loading (gx to open)

-- install lazy.nvim if not installed
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- install plugins
require("lazy").setup({
  -- big list of plugins: https://github.com/altermo/vim-plugin-list#jump-list (gx to open)
  -- popular neovim plugins: https://vimawesome.com/?q=tag:neovim (gx to open)

  -- use { and } to jump between empty lines between plugins

  {
    "folke/tokyonight.nvim",
    -- nice default color scheme,
    -- which supports many plugins (like statusbars) out of the box
    -- dark/light switching, etc
    -- https://github.com/folke/tokyonight.nvim (gx to open)
    lazy = false,
    priority = 1000,
    opts = {
      style = "storm",
      light_style = "night",
      day_brightness = 0.3
    },
  },

  {
    "folke/which-key.nvim",
    -- when starting to press keys, a list of possible keybindings is shown
    event = "VeryLazy",
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
    opts = {}
  },

  {
    "numToStr/Comment.nvim",
    -- comment lines with gcc, selections with gc
    lazy = false,
    opts = {}
  },

  {
    -- a popular fuzzy finder
    -- files, live grep, buffers, recent files, etc
    -- https://github.com/nvim-telescope/telescope.nvim (gx to open)
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    lazy = false, -- so that telescope works when starting vim with telescope from the command line
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = {
      { '<leader>e', '<cmd>Telescope find_files<cr>', desc = 'open files' },
      { '<leader>a', '<cmd>Telescope live_grep<cr>',  desc = 'live grep' },
      { '<leader>r', '<cmd>Telescope oldfiles<cr>',   desc = 'open recent files' },
      { '<leader>b', '<cmd>Telescope buffers<cr>',    desc = 'open recent files' }
    },
    opts = {
      pickers = {
        find_files = {
          -- hidden = true, -- will still show the inside of `.git/` as it's not `.gitignore`d.
          find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*" }, -- use ripgrep, find hidden files and folders except .git/
        },
        live_grep = {
          additional_args = { "--hidden", "--glob", "!**/.git/*" }, -- search in hidden files and folders except .git/
        },
      },
    }
  },

  {
    "neovim/nvim-lspconfig",
    -- language server protocol configurations
    -- for keybindings: https://github.com/neovim/nvim-lspconfig?tab=readme-ov-file#suggested-configuration
    init = function()
      -- list of supported language servers here:
      -- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md (gx to open)

      require 'lspconfig'.lua_ls.setup {
        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" },
            },
          },
        },
      }

      -- format on save
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = { "*" },
        command = "lua vim.lsp.buf.format()",
      })

    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    -- syntax highlighting
    -- https://github.com/nvim-treesitter/nvim-treesitter#readme
    -- with nix home-manager, all treesitter grammars can be installed in one go:
    -- programs.neovim.plugins = [
    --   pkgs.vimPlugins.nvim-treesitter.withAllGrammars
    -- ];
    build = ":TSUpdate",
    config = function()
      local configs = require("nvim-treesitter.configs")
      configs.setup({
        -- ...
      })
    end
  },

})


-- vimcustom (* to jump to index)

-- Restore cursor position
vim.api.nvim_create_autocmd({ "BufReadPost" }, {
  pattern = { "*" },
  callback = function()
    vim.api.nvim_exec('silent! normal! g`"zv', false)
  end,
})
```
