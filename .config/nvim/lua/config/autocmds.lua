-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

vim.api.nvim_create_autocmd(
-- automatically close terminal when process exited
  { "TermClose" }, {
    pattern = "*",
    command = "if !v:event.status | exe 'bdelete! '..expand('<abuf>') | endif",
  }
)
