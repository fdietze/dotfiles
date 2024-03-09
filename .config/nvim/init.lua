-- old: /home/felix.old-2024-03-01/.vimrc  (gf to open)
-- old: /home/felix.old-2024-03-01/.config/nvim.bak.astronvim-2024-02-27/lua/user

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
vim.opt.signcolumn = "yes" -- always show signcolumn, even if there are no diagnostics
vim.opt.gdefault = true -- by default substitute all occurrences in line with :s/.../.../g
vim.opt.breakindent = true -- indent wrapped lines
vim.opt.ignorecase = true -- search case insensitivity
vim.opt.smartcase = true -- uppercase search triggers case sensitivity
vim.opt.list = true
vim.opt.listchars = { tab = '⊳ ', trail = '·' } -- display whitespaces
vim.opt.history = 10000 -- keep x lines of command line history
vim.opt.backup = true -- file backups on save
vim.opt.backupdir = vim.env.HOME .. '/.local/state/nvim/backup/'
vim.opt.undofile = true -- persistent undo
vim.opt.viminfo = "'10000,<1000,s1000" -- adjust vim file history https://vi.stackexchange.com/a/26037

-- tab size 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true          -- use spaces instead of tabs

vim.opt.formatoptions:remove("o") -- don't continue comments with o


-- vimkeybindings (* to jump to index)
-- The descriptions can be read by plugins, like https://github.com/folke/which-key.nvim (gx to open)
-- old: /home/felix.old-2024-03-01/.vimrc_keybindings  (gf to open)
vim.g.mapleader = " " -- set leader to space
-- well established
vim.keymap.set('n', 'ä', '<cmd>q<cr>', { desc = 'quit' })
vim.keymap.set('n', 'ö', '<cmd>update<cr>', { desc = 'save' })
vim.keymap.set('n', 'ü', '<cmd>bdelete<cr>', { desc = 'close buffer' })
-- incubator

for _, mode in ipairs({ 'n', 'v' }) do
  vim.keymap.set(mode, 'Λ', '<C-W>k', { desc = 'focus window up (neo mod6+l)' })
  vim.keymap.set(mode, '∀', '<C-W>j', { desc = 'focus window down (neo mod6+a)' })
  vim.keymap.set(mode, '∫', '<C-W>h', { desc = 'focus window left (neo mod6+i)' })
  vim.keymap.set(mode, '∃', '<C-W>l', { desc = 'focus window right (neo mod6+e)' })
  vim.keymap.set(mode, 'Φ', '<C-W>_', { desc = 'maximize window right (neo mod6+f)' })
  vim.keymap.set(mode, '∂', '<cmd>ToggleTerm direction=horizontal start_in_insert=true<cr>',
    { desc = 'open terminal (neo mod6+t)' })
end

-- switch buffers with l, L
vim.keymap.set('n', 'l', '<cmd>bnext<cr>', { desc = 'next buffer' })
vim.keymap.set('n', 'L', '<cmd>bprev<cr>', { desc = 'prev buffer' })
vim.keymap.set('n', '<leader>vv', '<cmd>edit ~/.config/nvim/init.lua<cr>', { desc = 'edit init.lua' })
vim.keymap.set('n', '<leader>vt', '<cmd>edit ~/todo.md<cr>', { desc = 'edit todo.md' })
vim.keymap.set('n', 'h', "<cmd>let @/ = expand('<cword>')<cr>:set hls<cr>", { desc = 'highlight word under cursor' })
vim.keymap.set('n', '<leader>/', '<cmd>nohls<cr>', { desc = 'clear search highlight' })
vim.keymap.set('n', "<leader>p", "v$<Left>pgvy", { desc = 'paste over rest of line' })

vim.keymap.set('n', 'Y', 'y$', { desc = 'yank till end of line. (Y behaves like D and C)' })
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

vim.keymap.set('n', '<leader>gs', '<cmd>nohlsearch<CR>:term tig status<CR>i', { desc = 'launch tig status' })

vim.keymap.set('v', 'p', 'pgvy', { desc = "keep clipboard when pasting over selection" })
vim.keymap.set('v', '>', '>gv', { desc = ">, keep selection when indenting" })
vim.keymap.set('v', '<', '<gv', { desc = "<, keep selection when indenting" })
vim.keymap.set('v', '=', '=gv', { desc = "=, keep selection when indenting" })
vim.keymap.set('n', 'ß', '@q', { desc = "run macro 'q'" })

-- smart home
vim.keymap.set('n', '<Home>', "col('.') == match(getline('.'), '\\S') + 1 ? '<Home>' : '^'", { expr = true })
vim.keymap.set('i', '<Home>', "col('.') == match(getline('.'), '\\S') + 1 ? '<Home>' : '<C-O>^", { expr = true })


-- vimplugins (* to jump to index)
-- plugin manager: lazy.nvim
-- popular plugin manager as of 2024.
-- lazy.nvim loads plugins on demand for fast startup times.
-- events wich trigger a plugin load, may be vim-start, keybindings, filetypes, etc.
-- it also provides a nice way to configure plugins.
-- https://github.com/folke/lazy.nvim (gx to open)

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
    -- for light color scheme
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      color_overrides = {
        latte = {
          base = "#FFFFFF",
        },
      }
    }
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
    -- nice default status bar
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      options = {
        icons_enabled = true,
        theme = 'auto',
        component_separators = '', -- { left = '|', right = '|' },
        section_separators = '',   -- { left = '', right = '' },
        disabled_filetypes = {
          statusline = { 'neo-tree' },
          winbar = { 'neo-tree' },
        },
        ignore_focus = {},
        always_divide_middle = true,
        globalstatus = false,
        refresh = {
          statusline = 1000,
          tabline = 1000,
          winbar = 1000,
        }
      },
      sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = { 'filename' },
        lualine_x = { 'filetype' },
        lualine_y = {},
        lualine_z = { 'location' }
      },
      inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = {},
        lualine_x = {},
        lualine_y = {},
        lualine_z = {}
      },
      tabline = {},
      winbar = {
        lualine_a = { { 'buffers', symbols = { modified = ' ✱', alternate_file = '' } } },
        lualine_b = { { '%=' } }, -- workaround, so that buffers doesn't expand
      },
      inactive_winbar = {
        lualine_a = { 'filename' },
      },
      extensions = {}
    }
  },

  {
    "kylechui/nvim-surround",
    -- surround text with ys, change with cs, delete with ds
    version = "*", -- Use for stability; omit to use `main` branch for the latest features
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup({
        -- Configuration here, or leave empty to use defaults
      })
    end
  },

  {
    "nvim-neo-tree/neo-tree.nvim",
    -- file tree
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
      "MunifTanjim/nui.nvim",
      -- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
    },
    keys = {
      { '<leader>o', '<cmd>Neotree toggle reveal<cr>', desc = 'toggle file tree' }
    },
    opts = {
      auto_clean_after_session_restore = true,
      close_if_last_window = true,
      filesystem = {
        filtered_items = {
          visible = true
        },
        follow_current_file = { enabled = true },
      },
    }
  },

  {
    'NvChad/nvim-colorizer.lua',
    -- highlight color codes in files
    -- demo color: #8BF8E7
    lazy = false,
    config = function()
      require("colorizer").setup({
      })
    end
  },

  {
    'earthly/earthly.vim',
    -- syntax highlighting for Earthfiles
    ft = "Earthfile",
    config = function()
      vim.cmd([[autocmd FileType Earthfile setlocal commentstring=#\ %s]])
    end,
  },

  {
    "axkirillov/easypick.nvim",
    -- pick files from a list
    requires = 'nvim-telescope/telescope.nvim',
    keys = {
      { "<leader>vd", ":Easypick dotfiles<cr>", desc = "Dotfiles" },
    },
    config = function()
      local easypick = require("easypick")
      require("easypick").setup({
        pickers = {
          {
            name = "dotfiles",
            command = "list-dotfiles | xargs -L 1 -I {} echo $HOME/{}", -- ~/bin/list-dotfiles (gf to open)
            previewer = easypick.previewers.default()
          },
        }
      })
    end,
  },

  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local null_ls = require("null-ls")
      local sources = {
        -- null_ls.builtins.formatting.black,
        -- null_ls.builtins.formatting.goimports,
        -- null_ls.builtins.formatting.prettier,
        -- null_ls.builtins.formatting.stylua,
        -- null_ls.builtins.formatting.rustfmt,
        -- null_ls.builtins.formatting.csharpier,
        null_ls.builtins.formatting.alejandra, -- nix formatter
        -- null_ls.builtins.formatting.djlint,
        -- null_ls.builtins.formatting.terraform_fmt,
        -- null_ls.builtins.formatting.shfmt,
        -- null_ls.builtins.formatting.fourmolu,
      }
      local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
      null_ls.setup({
        sources = sources,
        on_attach = function(client, bufnr)
          if client.server_capabilities.documentFormattingProvider then
            vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
            vim.api.nvim_create_autocmd("BufWritePre", {
              group = augroup,
              buffer = bufnr,
              callback = function()
                vim.lsp.buf.format({ async = false })
              end,
            })
          end
        end,
      })
    end,
  },

  {
    "lewis6991/gitsigns.nvim",
    lazy = false,
    config = function()
      require("gitsigns").setup()
    end
  },

  {
    "RishabhRD/nvim-lsputils",
    -- show code actions, etc
    requires = { "RishabhRD/popfix" },
  },

  {
    "neovim/nvim-lspconfig",
    -- language server protocol configurations
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
      require 'lspconfig'.nixd.setup {}     -- nix
      require 'lspconfig'.marksman.setup {} --  markdown
      require 'lspconfig'.julials.setup {}  -- julia

      -- format on save
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = { "*" },
        command = "lua vim.lsp.buf.format()",
      })

      -- https://github.com/neovim/nvim-lspconfig?tab=readme-ov-file#suggested-configuration
    end,
  },
  -- {
  --   "dundalek/lazy-lsp.nvim",
  --   -- install lsp servers on demand using nix
  --   dependencies = { "neovim/nvim-lspconfig" },
  --   config = function()
  --     require("lazy-lsp").setup {}
  --   end
  -- },
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
  -- {
  -- 	'rmagatti/auto-session',
  -- 	config = function()
  -- 		require("auto-session").setup {
  -- 			log_level = "error",
  -- 			auto_session_suppress_dirs = { "~/", "~/Projects", "~/Downloads", "/" },
  -- 		}
  -- 	end
  -- },
  {
    "gioele/vim-autoswap",
    -- manage vim swapfiles
    lazy = false,

  },
  {
    "arp242/auto_mkdir2.vim",
    -- automatically create non-existing directories when writing a file
    lazy = false,
  },
  {
    "zbirenbaum/copilot.lua",
    -- AI completion, lua copy of the original
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      suggestion = {
        auto_trigger = true,
        keymap = {
          accept = "<C-tab>",
          accept_word = "<C-t>",
          accept_line = false,
          next = "<C-n>",
          dismiss = "<C-,>",
        },
      },
      filetypes = {
        yaml = true,
        markdown = false,
        gitcommit = true,
        json = true,
      },
    },
  },
  { 'akinsho/toggleterm.nvim',             version = "*", config = true },

  {
    "AndrewRadev/switch.vim",
    -- cycle between words
    keys = { "gs", desc = "cycle wordes, e.g. true <-> false" },
    config = function()
      vim.g.switch_custom_definitions = {
        { "on",         "off" },
        { "==",         "!=" },
        { "_",          "-" },
        { " < ",        " > " },
        { "<=",         ">=" },
        { " + ",        " - " },
        { "-=",         "+=" },
        { "and",        "or" },
        { "if",         "unless" },
        { "YES",        "NO" },
        { "yes",        "no" },
        { "first",      "last" },
        { "else",       "else if" },
        { "max",        "min" },
        { "px",         "%",       "em" },
        { "left",       "right" },
        { "top",        "bottom" },
        { "margin",     "padding" },
        { "height",     "width" },
        { "absolute",   "relative" },
        { "horizontal", "vertical" },
        { "show",       "hide" },
        { "visible",    "hidden" },
        { "add",        "remove" },
        { "up",         "down" },
        { "before",     "after" },
        { "slow",       "fast" },
        { "small",      "large" },
        { "even",       "odd" },
        { "inside",     "outside" },
        { "with",       "extends" },
        { "class",      "object",  "trait" },
        { "def",        "val" },
      }
    end,
  },

  { "lukas-reineke/indent-blankline.nvim", main = "ibl",  opts = {} },

  -- {
  -- 	"notjedi/nvim-rooter.lua",
  -- 	event = "BufReadPost",
  -- 	config = function() require("nvim-rooter").setup() end,
  -- },
  {
    "terryma/vim-multiple-cursors",
    lazy = false,
    -- keys = {
    --   { "<c-n>", desc = "multiple cursors on current word" },
    -- },
    config = function()
      vim.g.multi_cursor_exit_from_visual_mode = 0
      vim.g.multi_cursor_exit_from_insert_mode = 0
    end,
  },
})


-- vimcustom (* to jump to index)

-- load dark or light color scheme
local theme_file = io.open(os.getenv("HOME") .. "/.theme", "r")
local system_theme = "dark"
if theme_file then
  if theme_file:read("*a"):find("light") then
    system_theme = "light"
  end
  theme_file:close()
end
if system_theme == "dark" then
  vim.opt.background = "dark"
  vim.cmd [[colorscheme tokyonight-storm]]
else
  vim.opt.background = "light"
  vim.cmd [[colorscheme catppuccin-latte]]
end


-- Restore cursor position
vim.api.nvim_create_autocmd({ "BufReadPost" }, {
  pattern = { "*" },
  callback = function()
    vim.api.nvim_exec('silent! normal! g`"zv', false)
  end,
})


-- run commands, when saving specific files
-- vim.api.nvim_create_autocmd("BufWritePost", {
-- 	pattern = vim.fn.expand("~") .. "/nixos/*.nix",
-- 	callback = function()
-- 		-- Command to execute
-- 		local cmd = "sudo nixos-rebuild switch"
--
-- 		-- Open a terminal in a new split and run the command
-- 		vim.cmd("belowright split | terminal " .. cmd)
-- 	end,
-- })



-- vim.api.nvim_create_autocmd("BufWritePost", {
-- 	pattern = vim.fn.expand("~") .. "/nixos/*.nix",
-- 	callback = function()
-- 		local cmd = "sudo nixos-rebuild switch\n"
-- 		local term_buf_var = "nixos_rebuild_term_buf"
--
-- 		-- Try to find an existing terminal buffer
-- 		local term_buf = vim.g[term_buf_var]
-- 		if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
-- 			-- Focus the window containing the terminal, if it exists
-- 			local found = false
-- 			for _, win in ipairs(vim.api.nvim_list_wins()) do
-- 				if vim.api.nvim_win_get_buf(win) == term_buf then
-- 					vim.api.nvim_set_current_win(win)
-- 					found = true
-- 					break
-- 				end
-- 			end
-- 			if not found then
-- 				-- If the terminal buffer isn't visible in any window, open it in a new split
-- 				vim.cmd("belowright split | buffer " .. term_buf)
-- 			end
-- 		else
-- 			-- Open a new terminal in a split if no existing terminal buffer was found
-- 			vim.cmd("belowright split | terminal")
-- 			term_buf = vim.api.nvim_get_current_buf()
-- 			-- Save the terminal buffer handle globally for later reuse
-- 			vim.g[term_buf_var] = term_buf
-- 		end
--
-- 		-- Send the command to the terminal
-- 		vim.fn.chansend(vim.api.nvim_buf_get_option(term_buf, 'channel'), cmd)
-- 	end,
-- })
--
--



-- highlight existing file paths
-- Define the Lua function for underlining existing file paths
local function underline_existing_paths()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local ns_id = vim.api.nvim_create_namespace('underline_paths')

  -- Clear existing underlines
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Define a Lua pattern for file paths, excluding spaces within paths
  local pattern = "([~/][%w%._%-/]+[%w%._%-])"

  for i, line in ipairs(lines) do
    for file_path in line:gmatch(pattern) do
      -- Expand ~ to the home directory
      local expanded_path = file_path:gsub("^~", os.getenv("HOME") or "")

      -- Check if the file exists
      if vim.fn.filereadable(expanded_path) == 1 or vim.fn.isdirectory(expanded_path) == 1 then
        local start_pos, end_pos = line:find(file_path, 1, true)
        if start_pos and end_pos then
          -- Highlight the file path
          vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'UnderlinedFilePath', i - 1, start_pos - 1, end_pos)
        end
      end
    end
  end
end

-- Create the highlight group
vim.cmd [[highlight UnderlinedFilePath gui=underline cterm=underline]]

-- Apply the highlight using an autocommand
vim.api.nvim_create_autocmd(
  { "BufRead", "BufEnter", "CursorHold", "InsertLeave", "TextChanged", "TextChangedI", "TextChangedP" }, {
    pattern = "*",
    callback = underline_existing_paths,
  })
