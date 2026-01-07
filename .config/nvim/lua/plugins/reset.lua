-- disable Lazyvim defaults I don't need
-- https://www.lazyvim.org/configuration/plugins#%EF%B8%8F-adding--disabling-plugin-keymaps

return {
  -- disable mason because I'm on NixOS
  -- https://github.com/LazyVim/LazyVim/issues/445#issuecomment-1473273620
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "mason-org/mason.nvim", enabled = false },
  { "folke/persistence.nvim", enabled = false },
  { "folke/yanky.nvim", enabled = false },
  -- { "nvimdev/dashboard-nvim", enabled = false },
  { "stevearc/aerial.nvim", enabled = false },
  { "nvim-mini/mini.pairs", enabled = false },
  { "nvim-mini/mini.surround", enabled = false },
  { "gbprod/yanky.nvim", enabled = false },
  { "folke/todo-comments.nvim", enabled = false },
  { "rafamadriz/friendly-snippets", enabled = false },
  -- { "markdown-preview.nvim", enabled = false },
  -- { "iamcco/markdown-preview.nvim", enabled = false },
  -- { "MeanderingProgrammer/render-markdown.nvim", enabled = false },
  -- { "headlines.nvim", enabled = false },
  -- {
  --   "nvim-telescope/telescope.nvim",
  --   keys = {
  --     { "<leader>gs", false },
  --     { "<leader>/", false },
  --   },
  -- },
  {
    "folke/flash.nvim",
    enabled = false,
    keys = {
      { "s", false },
      -- { "S", mode = { "n", "o", "x" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      -- { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      -- { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      -- { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
  },
  {
    -- https://github.com/LazyVim/LazyVim/issues/238#issuecomment-1466793744
    "LazyVim/LazyVim",
    opts = {
      defaults = {
        autocmds = true, -- lazyvim.config.autocmds
        keymaps = false, -- lazyvim.config.keymaps
        options = true, -- lazyvim.config.options
      },
    },
  },
  -- {
  --   "folke/noice.nvim",
  --   enabled = true,
  --   opts = {
  --     -- cmdline = {
  --     --   view = 'cmdline' -- classic command line at the bottom
  --     -- },
  --     -- notify = {
  --     --   enabled = true,
  --     --   view = 'split'
  --     -- },
  --     -- routes = {
  --     --   {
  --     --     filter = {
  --     --       event = "echo",
  --     --     },
  --     --     view = "split",
  --     --   },
  --     -- },
  --     presets = {
  --       -- bottom_search = true,
  --       -- command_palette = true,
  --       -- long_message_to_split = true,
  --     },
  --   },
  -- },
  {
    "nvim-neo-tree/neo-tree.nvim",
    keys = {
      { "<leader>e", false }, -- mapped to <leader>o
      { "<leader>E", false },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      sections = {
        lualine_z = {}, -- remove clock
      },
    },
  },
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        enabled = false,
      },
      notifier = {
        level = vim.log.levels.WARN,
      },
    },
  },
  -- {
  --   "nvim-cmp",
  --   opts = function(_, opts)
  --     -- disable ghost text
  --     opts.experimental.ghost_text = false
  --   end,
  -- },
}
