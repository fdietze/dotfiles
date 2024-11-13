-- old lua: /home/felix/.config/nvim.bak/init.lua

return {
  {
    -- file manager
    "nvim-neo-tree/neo-tree.nvim",
    keys = {
      { "<leader>o", "<leader>fe", desc = "Explorer NeoTree (Root Dir)", remap = true },
      { "<leader>O", "<leader>fE", desc = "Explorer NeoTree (cwd)", remap = true },
    },
    opts = {
      window = {
        position = "right",
      },
      -- auto_clean_after_session_restore = true,
      -- close_if_last_window = true, -- buggy
      filesystem = {
        filtered_items = {
          visible = true,
        },
      },
    },
  },

  {
    -- a popular fuzzy finder
    -- files, live grep, buffers, recent files, etc
    -- https://github.com/nvim-telescope/telescope.nvim
    "nvim-telescope/telescope.nvim",
    keys = {
      { "<leader>e", "<cmd>Telescope find_files<cr>", desc = "open files" },
      { "<leader>a", "<cmd>Telescope live_grep<cr>", desc = "live grep" },
      { "<leader>A", "<cmd>Telescope live_grep<cr><C-r><C-w>", desc = "live grep word under cursor" }, -- TODO!
      { "<leader>vr", "<cmd>Telescope oldfiles<cr>", desc = "open recent files" },
      -- { '<leader>b',  '<cmd>Telescope buffers<cr>',             desc = 'open buffers' }
    },
    opts = {
      pickers = {
        live_grep = {
          -- , "--fixed-strings"
          additional_args = { "--hidden", "--glob", "!**/.git/*" }, -- search in hidden files and folders except .git/
        },
      },
    },
  },

  -- { 'nvim-telescope/telescope-fzf-native.nvim', build = 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release' },

  {
    "axkirillov/easypick.nvim",
    -- pick files from a list
    requires = "nvim-telescope/telescope.nvim",
    keys = {
      { "<leader>vd", ":Easypick dotfiles<cr>", desc = "Dotfiles" },
    },
    config = function()
      local easypick = require("easypick")
      require("easypick").setup({
        pickers = {
          {
            name = "dotfiles",
            command = 'list-dotfiles | sed "s|^|~/|"', -- ~/bin/list-dotfiles (gf to open)
            previewer = easypick.previewers.default(),
          },
        },
      })
    end,
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
    end,
  },

  {
    "brenton-leighton/multiple-cursors.nvim",
    version = "*", -- Use the latest tagged version
    opts = {}, -- This causes the plugin setup function to be called
    keys = {
      {
        "<C-Up>",
        "<Cmd>MultipleCursorsAddUp<CR>",
        mode = { "n", "i", "x" },
        desc = "Add cursor and move up",
      },
      {
        "<C-Down>",
        "<Cmd>MultipleCursorsAddDown<CR>",
        mode = { "n", "i", "x" },
        desc = "Add cursor and move down",
      },
      {
        "<C-LeftMouse>",
        "<Cmd>MultipleCursorsMouseAddDelete<CR>",
        mode = { "n", "i" },
        desc = "Add or remove cursor",
      },

      {
        "<C-n>",
        "<Cmd>MultipleCursorsAddJumpNextMatch<CR>",
        mode = { "n", "x" },
        desc = "Add cursor and jump to next cword",
      },
      {
        "<C-x>",
        "<Cmd>MultipleCursorsJumpNextMatch<CR>",
        mode = { "n", "x" },
        desc = "Jump to next cword",
      },
    },
  },

  {
    "AndrewRadev/switch.vim",
    -- cycle between words
    -- examples: true, on, px
    keys = { "gs", desc = "cycle wordes, e.g. true <-> false" },
    config = function()
      vim.g.switch_custom_definitions = {
        { "on", "off" },
        { "==", "!=" },
        { " < ", " > " },
        { "<=", ">=" },
        { " + ", " - " },
        { "-=", "+=" },
        { "and", "or" },
        { "if", "unless" },
        { "YES", "NO" },
        { "yes", "no" },
        { "first", "last" },
        { "else", "else if" },
        { "max", "min" },
        { "px", "%", "em" },
        { "left", "right" },
        { "top", "bottom" },
        { "margin", "padding" },
        { "height", "width" },
        { "absolute", "relative" },
        { "horizontal", "vertical" },
        { "show", "hide" },
        { "visible", "hidden" },
        { "add", "remove" },
        { "up", "down" },
        { "before", "after" },
        { "slow", "fast" },
        { "small", "large" },
        { "even", "odd" },
        { "inside", "outside" },
        { "with", "extends" },
        { "class", "object", "trait" },
        { "def", "val" },
      }
    end,
  },

  {
    "NvChad/nvim-colorizer.lua",
    -- highlight color codes in files
    -- demo colors: #8BF8E7, salmon
    lazy = false,
    config = function()
      require("colorizer").setup({})
    end,
  },

  {
    "earthly/earthly.vim",
    -- syntax highlighting for Earthfiles
    ft = "Earthfile",
    config = function()
      vim.cmd([[autocmd FileType Earthfile setlocal commentstring=#\ %s]])
    end,
  },

  {
    "mrcjkb/rustaceanvim",
    opts = {
      server = {
        default_settings = {
          -- rust-analyzer language server configuration
          ["rust-analyzer"] = {
            cargo = {
              -- To prevent rustanalyzer from locking the target dir (blocking cargo build/run)
              -- https://github.com/rust-lang/rust-analyzer/issues/6007#issuecomment-1523204067
              extraEnv = { CARGO_PROFILE_RUST_ANALYZER_INHERITS = "dev", CC = "gcc" },
              extraArgs = { "--profile", "rust-analyzer" },
            },
            diagnostics = {
              -- show code, even if disabled via feature flags
              disabled = { "inactive-code" },
            },
            -- Add clippy lints for Rust.
            -- TODO: already enabled by default?
            -- check = {
            --   command = "clippy",
            -- },
          },
        },
      },
    },
  },
  {
    "MagicDuck/grug-far.nvim",
    config = function()
      require("grug-far").setup({
        engines = {
          ripgrep = {
            path = "rg",
            extraArgs = "--hidden",
          },
        },
        -- engines = {
        --   -- see https://github.com/BurntSushi/ripgrep
        --   ripgrep = {
        --     -- extraArgs = "--hidden --glob !**/.git/*", -- TODO: not working...
        --     extraArgs = "--hidden", -- TODO: not working...
        --   },
        -- }
      })
    end,
  },
  { "vmchale/just-vim" },
  -- {
  --   "hrsh7th/nvim-cmp",
  --   opts = function(_, opts)
  --     local cmp = require("cmp")
  --     table.insert(opts.sorting, {
  --       comparators = {
  --         cmp.config.compare.offset,
  --         cmp.config.compare.exact,
  --         cmp.config.compare.score,
  --         cmp.config.compare.recently_used,
  --         -- require("cmp-under-comparator").under,
  --         cmp.config.compare.kind,
  --       },
  --     })
  --     --   return {
  --     --     -- preselect = auto_select and cmp.PreselectMode.Item or cmp.PreselectMode.None,
  --     --     -- experimental = {
  --     --     --   ghost_text = {
  --     --     --     hl_group = "CmpGhostText",
  --     --     --   },
  --     --     -- },
  --     --     sorting =
  --     --   }
  --   end,
  -- },
  -- {
  --   'huggingface/llm.nvim',
  --   opts = {
  --     -- cf Setup
  --   }
  -- },
  -- {
  --   "jackMort/ChatGPT.nvim",
  --   event = "VeryLazy",
  --   config = function()
  --     require("chatgpt").setup({
  --       api_key_cmd = "secret-tool lookup ENV OPENAI_API_KEY"
  --     })
  --   end,
  --   dependencies = {
  --     "MunifTanjim/nui.nvim",
  --     "nvim-lua/plenary.nvim",
  --     "folke/trouble.nvim", -- optional
  --     "nvim-telescope/telescope.nvim"
  --   }
  -- },
  -- {
  --   "robitx/gp.nvim",
  --   config = function()
  --     local conf = {
  --       -- https://github.com/Robitx/gp.nvim?tab=readme-ov-file#5-configuration
  --       openai_api_key = { "secret-tool", "lookup", "ENV", "OPENAI_API_KEY" },
  --     }
  --     require("gp").setup(conf)
  --
  --     -- Setup shortcuts here (see Usage > Shortcuts in the Documentation/Readme)
  --   end,
  -- },
  {
    "nvim-flutter/flutter-tools.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- 'stevearc/dressing.nvim', -- optional for vim.ui.select
    },
    config = true,
  },
}
