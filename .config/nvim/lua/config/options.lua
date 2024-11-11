-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- RESET
vim.opt.relativenumber = false


-- OPTIONS
vim.opt.gdefault = true -- by default substitute all occurrences in line with :s/.../.../g
vim.opt.listchars = { tab = '⊳ ', trail = '·' } -- display whitespaces
vim.opt.viminfo = "'10000,<1000,s1000,h" -- adjust vim file history https://vi.stackexchange.com/a/26037
-- vim.opt.wildmode = 'longest,list:lastused,full'
vim.opt.virtualedit = { 'block', 'onemore' } -- the cursor can be positioned where there is no actual character.
vim.opt.startofline = false -- move the cursor to the first non-blank of the line: CTRL-D, CTRL-U, switching buffers, ...
vim.opt.wrap = true
vim.opt.linebreak = true -- break only at word boundary
vim.opt.breakindent = true -- indent wrapped lines
vim.opt.breakindentopt = "shift:2"


if vim.g.neovide then
  vim.o.guifont = "Ubuntu Mono:h8"
  -- vim.o.guifont = "Monospace:h9"
end
