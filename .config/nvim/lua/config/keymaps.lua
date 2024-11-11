-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- old: /home/felix/backup-gurke-2024-03-01/.vimrc_keybindings
-- old lua: /home/felix/.config/nvim.bak/init.lua


vim.keymap.set({ 'n', 'v' }, 'ä', '<cmd>q<cr>', { desc = 'quit' })
vim.keymap.set({ 'n', 'v' }, 'ö', '<cmd>update<cr>', { desc = 'save' })
vim.keymap.set({ 'n', 'v' }, 'ü', LazyVim.ui.bufremove, { desc = 'close buffer' })
vim.keymap.set({ 'n', 'v' }, '<leader>ü', '<cmd>BufOnly<cr>', { desc = 'close all buffers except the current one' })

-- -- switch buffers with l, L
vim.keymap.set({ 'n', 'v' }, 'l', '<cmd>bnext<cr>', { desc = 'next buffer' })
vim.keymap.set({ 'n', 'v' }, 'L', '<cmd>bprev<cr>', { desc = 'prev buffer' })

-- vim.keymap.set('n', '<leader>vv', '<cmd>edit ~/.config/nvim/init.lua<cr>', { desc = 'edit init.lua' })
vim.keymap.set('n', '<leader>vv', LazyVim.pick.config_files(), { desc = 'edit config files' })
vim.keymap.set('n', '<leader>vh', '<cmd>edit ~/nixos/home.nix<cr>', { desc = 'edit init.lua' })
vim.keymap.set('n', '<leader>vn', '<cmd>edit ~/nixos/configuration.nix<cr>', { desc = 'edit init.lua' })
vim.keymap.set('n', '<leader>vt', '<cmd>edit ~/MEGAsync/notes/todo.md<cr>', { desc = 'edit todo.md' })


vim.keymap.set('v', '>', '>gv', { desc = ">, keep selection when indenting" })
vim.keymap.set('v', '<', '<gv', { desc = "<, keep selection when indenting" })
vim.keymap.set('v', '=', '=gv', { desc = "=, keep selection when indenting" })

vim.keymap.set({ 'n', 'v' }, 'Λ', '<C-W>k', { desc = 'focus window up (neo mod6+l)' })
vim.keymap.set({ 'n', 'v' }, '∀', '<C-W>j', { desc = 'focus window down (neo mod6+a)' })
vim.keymap.set({ 'n', 'v' }, '∫', '<C-W>h', { desc = 'focus window left (neo mod6+i)' })
vim.keymap.set({ 'n', 'v' }, '∃', '<C-W>l', { desc = 'focus window right (neo mod6+e)' })
vim.keymap.set({ 'n', 'v' }, 'Φ', '<C-W>_', { desc = 'maximize window right (neo mod6+f)' })
vim.keymap.set({ 'n', 'v' }, '∂', '<cmd>ToggleTerm direction=horizontal start_in_insert=true<cr>',
  { desc = 'open terminal (neo mod6+t)' })


vim.keymap.set('n', 'h', "<cmd>let @/ = expand('<cword>')<cr>:set hls<cr>", { desc = 'highlight word under cursor' }) -- todo: toggle
vim.keymap.set('n', '<leader>/', '<cmd>nohls<cr>', { desc = 'clear search highlight' })

vim.keymap.set('n', 'Y', 'y$', { desc = 'yank till end of line. (Y behaves like D and C)' })
vim.keymap.set('n', "<leader>p", "v$<Left>pgvy", { desc = 'paste over rest of line' })

vim.keymap.set({ 'n', 'v' }, '<leader>gs', '<cmd>nohlsearch<CR><cmd>term tig status<CR>i', { desc = 'launch tig status' })
-- vim.keymap.set('n', 'gf', ':e <cfile><cr>', { desc = 'edit/create file under cursor' })
-- vim.keymap.set('n', 'gf', function()
--   local filename = vim.fn.expand("<cfile>")
--   local newfilepath = vim.fn.expand('%:p:h') .. '/' .. filename
--
--   if vim.fn.filereadable(newfilepath) == 1 then
--     print("File already exists")
--     vim.cmd('normal <C-W>gf')
--   else
--     os.execute("touch " .. newfilepath)
--     print("File created: " .. newfilepath)
--     vim.cmd('normal <C-W>gf')
--   end
-- end, { noremap = true, silent = true })

vim.keymap.set('v', 'p', 'pgvy', { desc = "keep clipboard when pasting over selection" })
vim.keymap.set('n', 'ß', '@q', { desc = "run macro 'q'" })
-- vim.keymap.set({ 'n', 'v', 'i' }, '<C-Up>', 'g<Up>', { desc = "move visible line up" })
--
-- smart home
vim.keymap.set('n', '<Home>', function()
  return vim.fn.col('.') == vim.fn.match(vim.fn.getline('.'), '\\S') + 1 and '<Home>' or '^'
end, { expr = true })
vim.keymap.set('i', '<Home>', function()
  return vim.fn.col('.') == vim.fn.match(vim.fn.getline('.'), '\\S') + 1 and '<Home>' or '<C-O>^'
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

vim.keymap.set('n', '<leader>,', function() toggle_char_at_eol(',') end, { desc = 'toggle , at end of line' })
vim.keymap.set('n', '<leader>;', function() toggle_char_at_eol(';') end, { desc = 'toggle ; at end of line' })


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

local function keymapOptions(desc)
    return {
        noremap = true,
        silent = true,
        nowait = true,
        desc = "GPT prompt " .. desc,
    }
end

vim.keymap.set({"n", "i"}, "<C-g>c", "<cmd>GpChatNew<cr>", keymapOptions("New Chat"))
-- vim.keymap.set({"n", "i"}, "<C-g>t", "<cmd>GpChatToggle<cr>", keymapOptions("Toggle Chat"))
-- vim.keymap.set({"n", "i"}, "<C-g>f", "<cmd>GpChatFinder<cr>", keymapOptions("Chat Finder"))

vim.keymap.set("v", "<C-g>c", ":<C-u>'<,'>GpChatNew<cr>", keymapOptions("Visual Chat New"))
-- vim.keymap.set("v", "<C-g>p", ":<C-u>'<,'>GpChatPaste<cr>", keymapOptions("Visual Chat Paste"))
-- vim.keymap.set("v", "<C-g>t", ":<C-u>'<,'>GpChatToggle<cr>", keymapOptions("Visual Toggle Chat"))

vim.keymap.set({ "n", "i" }, "<C-g><C-x>", "<cmd>GpChatNew split<cr>", keymapOptions("New Chat split"))
-- vim.keymap.set({ "n", "i" }, "<C-g><C-v>", "<cmd>GpChatNew vsplit<cr>", keymapOptions("New Chat vsplit"))
-- vim.keymap.set({ "n", "i" }, "<C-g><C-t>", "<cmd>GpChatNew tabnew<cr>", keymapOptions("New Chat tabnew"))

-- vim.keymap.set("v", "<C-g><C-x>", ":<C-u>'<,'>GpChatNew split<cr>", keymapOptions("Visual Chat New split"))
-- vim.keymap.set("v", "<C-g><C-v>", ":<C-u>'<,'>GpChatNew vsplit<cr>", keymapOptions("Visual Chat New vsplit"))
-- vim.keymap.set("v", "<C-g><C-t>", ":<C-u>'<,'>GpChatNew tabnew<cr>", keymapOptions("Visual Chat New tabnew"))

-- Prompt commands
vim.keymap.set({"n", "i"}, "<C-g>r", "<cmd>GpRewrite<cr>", keymapOptions("Inline Rewrite"))
vim.keymap.set({"n", "i"}, "<C-g>a", "<cmd>GpAppend<cr>", keymapOptions("Append (after)"))
vim.keymap.set({"n", "i"}, "<C-g>b", "<cmd>GpPrepend<cr>", keymapOptions("Prepend (before)"))

vim.keymap.set("v", "<C-g>r", ":<C-u>'<,'>GpRewrite<cr>", keymapOptions("Visual Rewrite"))
vim.keymap.set("v", "<C-g>a", ":<C-u>'<,'>GpAppend<cr>", keymapOptions("Visual Append (after)"))
vim.keymap.set("v", "<C-g>b", ":<C-u>'<,'>GpPrepend<cr>", keymapOptions("Visual Prepend (before)"))
vim.keymap.set("v", "<C-g>i", ":<C-u>'<,'>GpImplement<cr>", keymapOptions("Implement selection"))

-- vim.keymap.set({"n", "i"}, "<C-g>gp", "<cmd>GpPopup<cr>", keymapOptions("Popup"))
-- vim.keymap.set({"n", "i"}, "<C-g>ge", "<cmd>GpEnew<cr>", keymapOptions("GpEnew"))
-- vim.keymap.set({"n", "i"}, "<C-g>gn", "<cmd>GpNew<cr>", keymapOptions("GpNew"))
-- vim.keymap.set({"n", "i"}, "<C-g>gv", "<cmd>GpVnew<cr>", keymapOptions("GpVnew"))
-- vim.keymap.set({"n", "i"}, "<C-g>gt", "<cmd>GpTabnew<cr>", keymapOptions("GpTabnew"))
--
-- vim.keymap.set("v", "<C-g>gp", ":<C-u>'<,'>GpPopup<cr>", keymapOptions("Visual Popup"))
-- vim.keymap.set("v", "<C-g>ge", ":<C-u>'<,'>GpEnew<cr>", keymapOptions("Visual GpEnew"))
-- vim.keymap.set("v", "<C-g>gn", ":<C-u>'<,'>GpNew<cr>", keymapOptions("Visual GpNew"))
-- vim.keymap.set("v", "<C-g>gv", ":<C-u>'<,'>GpVnew<cr>", keymapOptions("Visual GpVnew"))
-- vim.keymap.set("v", "<C-g>gt", ":<C-u>'<,'>GpTabnew<cr>", keymapOptions("Visual GpTabnew"))
--
-- vim.keymap.set({"n", "i"}, "<C-g>x", "<cmd>GpContext<cr>", keymapOptions("Toggle Context"))
-- vim.keymap.set("v", "<C-g>x", ":<C-u>'<,'>GpContext<cr>", keymapOptions("Visual Toggle Context"))

vim.keymap.set({"n", "i", "v", "x"}, "<C-g>s", "<cmd>GpStop<cr>", keymapOptions("Stop"))
vim.keymap.set({"n", "i", "v", "x"}, "<C-g>n", "<cmd>GpNextAgent<cr>", keymapOptions("Next Agent"))

-- optional Whisper commands with prefix <C-g>w
-- vim.keymap.set({"n", "i"}, "<C-g>ww", "<cmd>GpWhisper<cr>", keymapOptions("Whisper"))
-- vim.keymap.set("v", "<C-g>ww", ":<C-u>'<,'>GpWhisper<cr>", keymapOptions("Visual Whisper"))
--
-- vim.keymap.set({"n", "i"}, "<C-g>wr", "<cmd>GpWhisperRewrite<cr>", keymapOptions("Whisper Inline Rewrite"))
-- vim.keymap.set({"n", "i"}, "<C-g>wa", "<cmd>GpWhisperAppend<cr>", keymapOptions("Whisper Append (after)"))
-- vim.keymap.set({"n", "i"}, "<C-g>wb", "<cmd>GpWhisperPrepend<cr>", keymapOptions("Whisper Prepend (before) "))
--
-- vim.keymap.set("v", "<C-g>wr", ":<C-u>'<,'>GpWhisperRewrite<cr>", keymapOptions("Visual Whisper Rewrite"))
-- vim.keymap.set("v", "<C-g>wa", ":<C-u>'<,'>GpWhisperAppend<cr>", keymapOptions("Visual Whisper Append (after)"))
-- vim.keymap.set("v", "<C-g>wb", ":<C-u>'<,'>GpWhisperPrepend<cr>", keymapOptions("Visual Whisper Prepend (before)"))
--
-- vim.keymap.set({"n", "i"}, "<C-g>wp", "<cmd>GpWhisperPopup<cr>", keymapOptions("Whisper Popup"))
-- vim.keymap.set({"n", "i"}, "<C-g>we", "<cmd>GpWhisperEnew<cr>", keymapOptions("Whisper Enew"))
-- vim.keymap.set({"n", "i"}, "<C-g>wn", "<cmd>GpWhisperNew<cr>", keymapOptions("Whisper New"))
-- vim.keymap.set({"n", "i"}, "<C-g>wv", "<cmd>GpWhisperVnew<cr>", keymapOptions("Whisper Vnew"))
-- vim.keymap.set({"n", "i"}, "<C-g>wt", "<cmd>GpWhisperTabnew<cr>", keymapOptions("Whisper Tabnew"))
--
-- vim.keymap.set("v", "<C-g>wp", ":<C-u>'<,'>GpWhisperPopup<cr>", keymapOptions("Visual Whisper Popup"))
-- vim.keymap.set("v", "<C-g>we", ":<C-u>'<,'>GpWhisperEnew<cr>", keymapOptions("Visual Whisper Enew"))
-- vim.keymap.set("v", "<C-g>wn", ":<C-u>'<,'>GpWhisperNew<cr>", keymapOptions("Visual Whisper New"))
-- vim.keymap.set("v", "<C-g>wv", ":<C-u>'<,'>GpWhisperVnew<cr>", keymapOptions("Visual Whisper Vnew"))
-- vim.keymap.set("v", "<C-g>wt", ":<C-u>'<,'>GpWhisperTabnew<cr>", keymapOptions("Visual Whisper Tabnew"))



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
LazyVim.toggle.map("<leader>uf", LazyVim.toggle.format())
LazyVim.toggle.map("<leader>uF", LazyVim.toggle.format(true))
LazyVim.toggle.map("<leader>us", LazyVim.toggle("spell", { name = "Spelling" }))
LazyVim.toggle.map("<leader>uw", LazyVim.toggle("wrap", { name = "Wrap" }))
LazyVim.toggle.map("<leader>uL", LazyVim.toggle("relativenumber", { name = "Relative Number" }))
LazyVim.toggle.map("<leader>ud", LazyVim.toggle.diagnostics)
LazyVim.toggle.map("<leader>ul", LazyVim.toggle.number)
LazyVim.toggle.map("<leader>uc",
  LazyVim.toggle("conceallevel", { values = { 0, vim.o.conceallevel > 0 and vim.o.conceallevel or 2 } }))
LazyVim.toggle.map("<leader>uT", LazyVim.toggle.treesitter)
LazyVim.toggle.map("<leader>ub", LazyVim.toggle("background", { values = { "light", "dark" }, name = "Background" }))
if vim.lsp.inlay_hint then
  LazyVim.toggle.map("<leader>uh", LazyVim.toggle.inlay_hints)
end
