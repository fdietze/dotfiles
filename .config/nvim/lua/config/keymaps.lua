-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- old: /home/felix/backup-gurke-2024-03-01/.vimrc_keybindings
-- old lua: /home/felix/.config/nvim.bak/init.lua

vim.keymap.set({ "n", "v" }, "ä", "<cmd>q<cr>", { desc = "quit" })
vim.keymap.set({ "n", "v" }, "ö", ":w<cr>", { desc = "save" })
vim.keymap.set({ "n", "v" }, "ü", function()
  Snacks.bufdelete()
end, { desc = "Delete Buffer" })
vim.keymap.set({ "n", "v" }, "<leader>ü", function()
  Snacks.bufdelete.other()
end, { desc = "Delete Other Buffers" })

-- -- switch buffers with l, L
vim.keymap.set({ "n", "v" }, "l", "<cmd>bnext<cr>", { desc = "next buffer" })
vim.keymap.set({ "n", "v" }, "L", "<cmd>bprev<cr>", { desc = "prev buffer" })

vim.keymap.set("n", "<leader>vv", LazyVim.pick.config_files(), { desc = "edit vim config files" })
vim.keymap.set("n", "<leader>vh", "<cmd>edit ~/nixos/home.nix<cr>", { desc = "edit home.nix" })
vim.keymap.set("n", "<leader>vn", "<cmd>edit ~/nixos/configuration.nix<cr>", { desc = "edit configuration.nix" })
vim.keymap.set("n", "<leader>vt", "<cmd>edit ~/MEGAsync/notes/todo.md<cr>", { desc = "edit todo.md" })

vim.keymap.set("n", "<leader>e", "<cmd>FzfLua files<cr>", { desc = "open files" })
vim.keymap.set("n", "<leader>a", "<cmd>FzfLua live_grep<cr>", { desc = "live grep" })
vim.keymap.set("n", "<leader>A", "<cmd>FzfLua grep_cword<cr>", { desc = "live grep word under cursor" })
vim.keymap.set("n", "<leader>vr", "<cmd>FzfLua oldfiles<cr>", { desc = "open recent files" })

vim.keymap.set("v", ">", ">gv", { desc = ">, keep selection when indenting" })
vim.keymap.set("v", "<", "<gv", { desc = "<, keep selection when indenting" })
vim.keymap.set("v", "=", "=gv", { desc = "=, keep selection when indenting" })

vim.keymap.set({ "n", "v" }, "Λ", "<C-W>k", { desc = "focus window up (neo mod6+l)" })
vim.keymap.set({ "n", "v" }, "∀", "<C-W>j", { desc = "focus window down (neo mod6+a)" })
vim.keymap.set({ "n", "v" }, "∫", "<C-W>h", { desc = "focus window left (neo mod6+i)" })
vim.keymap.set({ "n", "v" }, "∃", "<C-W>l", { desc = "focus window right (neo mod6+e)" })
vim.keymap.set({ "n", "v" }, "Φ", "<C-W>_", { desc = "maximize window right (neo mod6+f)" })
vim.keymap.set(
  { "n", "v" },
  "∂",
  "<cmd>ToggleTerm direction=horizontal start_in_insert=true<cr>",
  { desc = "open terminal (neo mod6+t)" }
)

vim.keymap.set("n", "h", "<cmd>let @/ = expand('<cword>')<cr>:set hls<cr>", { desc = "highlight word under cursor" }) -- todo: toggle
vim.keymap.set("n", "<leader>/", "<cmd>nohls<cr>", { desc = "clear search highlight" })

vim.keymap.set("n", "Y", "y$", { desc = "yank till end of line. (Y behaves like D and C)" })
vim.keymap.set("n", "<leader>p", "v$<Left>pgvy", { desc = "paste over rest of line" })

vim.keymap.set(
  { "n", "v" },
  "<leader>gs",
  "<cmd>nohlsearch<CR><cmd>term tig status<CR>i",
  { desc = "launch tig status" }
)

vim.keymap.set("v", "p", "pgvy", { desc = "keep clipboard when pasting over selection" })
vim.keymap.set({ "n", "v" }, "ß", "@q", { desc = "run macro 'q'" })

-- smart home
vim.keymap.set("n", "<Home>", function()
  return vim.fn.col(".") == vim.fn.match(vim.fn.getline("."), "\\S") + 1 and "<Home>" or "^"
end, { expr = true })
vim.keymap.set("i", "<Home>", function()
  return vim.fn.col(".") == vim.fn.match(vim.fn.getline("."), "\\S") + 1 and "<Home>" or "<C-O>^"
end, { expr = true })

-- Toggle a specific character at the end of the current line
local function toggle_char_at_eol(target_char)
  local line_content = vim.api.nvim_get_current_line()

  if line_content:sub(-1) == target_char then
    -- Remove the character if it's at the end
    vim.api.nvim_set_current_line(line_content:sub(1, -2))
  else
    -- Add the character at the end
    vim.api.nvim_set_current_line(line_content .. target_char)
  end
end

vim.keymap.set("n", "<leader>,", function()
  toggle_char_at_eol(",")
end, { desc = "toggle , at end of line" })
vim.keymap.set("n", "<leader>;", function()
  toggle_char_at_eol(";")
end, { desc = "toggle ; at end of line" })

vim.keymap.set("n", "<leader>n", function()
  local has_errors = next(vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })) ~= nil
  if has_errors then
    vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR, float = true })
  else
    local has_warnings = next(vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })) ~= nil
    if has_warnings then
      vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.WARN, float = true })
    else
      vim.diagnostic.goto_next({ float = true })
    end
  end
end, { desc = "Jump to next LSP diagnostic" })

vim.keymap.set("n", "<a-cr>", vim.lsp.buf.code_action, { desc = "Code Actions" })

------------------------------------------------------------------------------------------
-- copied from https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- https://github.com/mhinz/vim-galore#saner-behavior-of-n-and-n
vim.keymap.set("n", "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next Search Result" })
vim.keymap.set("x", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
vim.keymap.set("o", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
vim.keymap.set("n", "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev Search Result" })
vim.keymap.set("x", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })
vim.keymap.set("o", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })

-- lazy
vim.keymap.set("n", "<leader>l", "<cmd>Lazy<cr>", { desc = "Lazy" })

-- quicklist
vim.keymap.set("n", "<leader>xl", "<cmd>lopen<cr>", { desc = "Location List" })
vim.keymap.set("n", "<leader>xq", "<cmd>copen<cr>", { desc = "Quickfix List" })
vim.keymap.set("n", "[q", vim.cmd.cprev, { desc = "Previous Quickfix" })
vim.keymap.set("n", "]q", vim.cmd.cnext, { desc = "Next Quickfix" })

-- formatting
vim.keymap.set({ "n", "v" }, "<leader>cf", function()
  LazyVim.format({ force = true })
end, { desc = "Format" })

-- diagnostic
-- local diagnostic_goto = function(next, severity)
--   local go = next and vim.diagnostic.goto_next or vim.diagnostic.goto_prev
--   severity = severity and vim.diagnostic.severity[severity] or nil
--   return function()
--     go({ severity = severity })
--   end
-- end
-- vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line Diagnostics" })
-- vim.keymap.set("n", "]d", diagnostic_goto(true), { desc = "Next Diagnostic" })
-- vim.keymap.set("n", "[d", diagnostic_goto(false), { desc = "Prev Diagnostic" })
-- vim.keymap.set("n", "]e", diagnostic_goto(true, "ERROR"), { desc = "Next Error" })
-- vim.keymap.set("n", "[e", diagnostic_goto(false, "ERROR"), { desc = "Prev Error" })
-- vim.keymap.set("n", "]w", diagnostic_goto(true, "WARN"), { desc = "Next Warning" })
-- vim.keymap.set("n", "[w", diagnostic_goto(false, "WARN"), { desc = "Prev Warning" })

-- toggle options
LazyVim.format.snacks_toggle():map("<leader>uf")
LazyVim.format.snacks_toggle(true):map("<leader>uF")
Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
Snacks.toggle.diagnostics():map("<leader>ud")
Snacks.toggle.line_number():map("<leader>ul")
Snacks.toggle
  .option("conceallevel", { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 })
  :map("<leader>uc")
Snacks.toggle.treesitter():map("<leader>uT")
Snacks.toggle.option("background", { off = "light", on = "dark", name = "Dark Background" }):map("<leader>ub")
if vim.lsp.inlay_hint then
  Snacks.toggle.inlay_hints():map("<leader>uh")
end

if vim.g.vscode then
  -- Use the API provided by the vscode-neovim extension

  vim.keymap.del("n", "<leader>e")
  vim.keymap.set("n", "<leader>e", function()
    require("vscode").action("workbench.action.quickOpen")
  end, { noremap = true, silent = true, desc = "VSCode: Quick Open (Files)" })

  vim.keymap.del("n", "l")
  vim.keymap.set("n", "l", function()
    require("vscode").action("workbench.action.nextEditor")
  end, { noremap = true, silent = true, desc = "VSCode: Next Editor Tab" })

  vim.keymap.del("n", "L")
  vim.keymap.set("n", "L", function()
    require("vscode").action("workbench.action.previousEditor")
  end, { noremap = true, silent = true, desc = "VSCode: Previous Editor Tab" })

  vim.keymap.del("n", "<leader>ü")
  vim.keymap.set("n", "<leader>ü", function()
    require("vscode").action("workbench.action.closeOtherEditors")
  end, { noremap = true, silent = true, desc = "VSCode: Close Other Editor Tabs" })

  -- vim.keymap.del("n", "ü")
  -- vim.keymap.set("n", "ü", function()
  --   require("vscode").action("workbench.action.closeEditor")
  -- end, { noremap = true, silent = true, desc = "VSCode: Close Editor" })
end
