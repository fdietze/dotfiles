-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- old lua: /home/felix/.config/nvim.bak/init.lua

-- RESET
vim.opt.relativenumber = false




-- vim.opt.cursorline = true
-- vim.opt.number = true -- show line numbers
-- vim.opt.confirm = true -- confirm before overwriting files
-- vim.opt.clipboard:append("unnamedplus") -- use system clipboard
-- vim.opt.signcolumn = "yes" -- always show signcolumn, even if there are no diagnostics
vim.opt.gdefault = true -- by default substitute all occurrences in line with :s/.../.../g
-- vim.opt.ignorecase = true -- search case insensitivity
-- vim.opt.smartcase = true -- uppercase search triggers case sensitivity
-- vim.opt.list = true
-- vim.opt.listchars = { tab = '⊳ ', trail = '·' } -- display whitespaces
-- vim.opt.history = 10000 -- keep x lines of command line history
-- vim.opt.backup = true -- file backups on save
-- vim.opt.backupdir = vim.env.HOME .. '/.local/state/nvim/backup/'
-- vim.opt.undofile = true -- persistent undo
-- vim.opt.viminfo = "'10000,<1000,s1000" -- adjust vim file history https://vi.stackexchange.com/a/26037
-- vim.opt.wildmode = 'longest,list:lastused,full'
--
-- -- tabs
-- vim.opt.tabstop = 2      -- size of a hard tabstop
-- vim.opt.softtabstop = 2  -- a combination of spaces and tabs are used to simulate tab stops at a width
-- vim.opt.shiftwidth = 2   -- size of an "indent"
-- vim.opt.expandtab = true -- use spaces instead of tabs
-- vim.opt.smarttab = true
-- vim.opt.virtualedit =
-- { 'block', 'onemore' }      -- { 'block', 'onemore' } -- the cursor can be positioned where there is no actual character.
-- vim.opt.startofline = false -- move the cursor to the first non-blank of the line: CTRL-D, CTRL-U, switching buffers, ...
--
-- -- wrapping and scrolling
vim.opt.wrap = true
vim.opt.linebreak = true   -- break only at word boundary
vim.opt.breakindent = true -- indent wrapped lines
vim.opt.breakindentopt = "shift:2"
-- vim.opt.scrolloff = 5      -- scroll to keep 5 lines above and below cursor
-- vim.opt.sidescrolloff = 5
-- vim.opt.sidescroll = 1     -- used when wrap is off
--
-- -- vim.opt.formatoptions:remove("o") -- don't continue comments with o
--
if vim.g.neovide then
  vim.o.guifont = "Ubuntu Mono:h8"
  -- vim.o.guifont = "Monospace:h9"
end
