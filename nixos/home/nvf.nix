{
  lib,
  pkgs,
  nvf,
  ...
}: {
  imports = [
    nvf.homeManagerModules.default
  ];

  # old: ~/.config/nvim.bak/lua/config/options.lua
  # old: ~/.config/nvim.bak/lua/config/keymaps.lua
  # old: ~/.config/nvim.bak/lua/plugins/custom.lua

  # nvf option: https://nvf.notashelf.dev/options.html
  # nvf reference configuration: https://github.com/NotAShelf/nvf/blob/main/configuration.nix

  # TODO:
  # - gs (cycle)

  programs.nvf = {
    enable = true;
    defaultEditor = true;
    settings = {
      vim = {
        vimAlias = true;
        viAlias = true;

        theme = {
          enable = true;
          name = "tokyonight";
          style = "moon";
        };

        lineNumberMode = "number";
        clipboard = {
          enable = true;
          providers.xclip.enable = true;
          registers = "unnamedplus";
        };

        lsp = {
          enable = true;
          formatOnSave = true;
          # lspSignature.enable = true;
          # trouble.enable = false;
          inlayHints.enable = true;
          lightbulb.enable = true;
          mappings = {
            goToDefinition = "gd";
            listReferences = "gr";
          };
        };

        languages = {
          enableFormat = true;
          enableTreesitter = true;
          enableExtraDiagnostics = true;

          nix.enable = true;
          ts.enable = true;
          json.enable = true;
          typst.enable = true;
          python.enable = true;
          just.enable = true;
          bash.enable = true;
          sql.enable = true;
          rust = {
            enable = true;
            # extensions.crates-nvim.enable = true;
          };
          # toml.enable = true;
          markdown = {
            enable = true;
            format.enable = false;
          };
          css.enable = true;
          html.enable = false;
        };

        # treesitter.context.enable = true;

        filetree.neo-tree.enable = true;
        # telescope.enable = true;
        fzf-lua.enable = true;

        terminal.toggleterm.enable = true;
        # statusline.lualine.enable = true;
        mini.statusline.enable = true;
        # tabline.nvimBufferline.enable = true;
        mini.tabline.enable = true;
        # autocomplete.nvim-cmp.enable = true;
        autocomplete.blink-cmp.enable = true;
        # mini.indentscope.enable = true;
        utility = {
          # multicursors.enable = true;
          # surround = true;
          snacks-nvim = {
            enable = true;
            setupOpts = {
              indent.enabled = true;
            };
          };
        };

        visuals = {
          # nvim-scrollbar.enable = true;
          fidget-nvim.enable = true;
          # nvim-web-devicons.enable = true;
          # nvim-cursorline.enable = true;
        };
        ui.illuminate.enable = true;

        # minimap = {
        #   minimap-vim.enable = false;
        #   codewindow.enable = true; # lighter, faster, and uses lua for configuration
        # };

        binds = {
          whichKey = {
            enable = true;
            setupOpts = {
              delay = 500;
            };
          };
          cheatsheet.enable = true;
        };

        git = {
          enable = true;
          gitsigns.enable = false;
        };

        autocmds = [
          {
            # automatically close terminal when process exited
            event = ["TermClose"];
            pattern = ["*"];
            command = "if !v:event.status | exe 'bdelete! '..expand('<abuf>') | endif";
          }
          {
            # restore cursor position
            event = ["BufReadPost"];
            pattern = ["*"];
            command = ''if line("'\"") >= 1 && line("'\"") <= line("$") && &ft !~# 'commit' | exe "normal! g`\"" | endif'';
          }
        ];

        # lazy.plugins = {
        #   "dial.nvim" = {
        #     package = pkgs.vimPlugins.dial-nvim;
        #     setupModule = "dial";
        #     keys = [
        #       {
        #         key = "<C-a>";
        #         mode = ["n" "v"];
        #         desc = "Increment";
        #         action = "function() return _G.dial(true) end";
        #         lua = true;
        #         expr = true;
        #         silent = true;
        #       }
        #       {
        #         key = "<C-x>";
        #         mode = ["n" "v"];
        #         desc = "Decrement";
        #         action = "function() return _G.dial(false) end";
        #         lua = true;
        #         expr = true;
        #         silent = true;
        #       }
        #       {
        #         key = "g<C-a>";
        #         mode = ["n" "x"];
        #         desc = "Increment";
        #         action = "function() return _G.dial(true, true) end";
        #         lua = true;
        #         expr = true;
        #         silent = true;
        #       }
        #       {
        #         key = "g<C-x>";
        #         mode = ["n" "x"];
        #         desc = "Decrement";
        #         action = "function() return _G.dial(false, true) end";
        #         lua = true;
        #         expr = true;
        #         silent = true;
        #       }
        #     ];
        #     after = ''
        #       local augend = require("dial.augend")
        #
        #       local dial_config = {
        #         dials_by_ft = {
        #           css = "css", vue = "vue", javascript = "typescript",
        #           typescript = "typescript", typescriptreact = "typescript",
        #           javascriptreact = "typescript", json = "json", lua = "lua",
        #           markdown = "markdown", sass = "css", scss = "css", python = "python",
        #         },
        #         groups = {
        #           default = {
        #             augend.integer.alias.decimal,
        #             augend.integer.alias.decimal_int,
        #             augend.integer.alias.hex,
        #             augend.date.alias["%Y/%m/%d"],
        #             augend.constant.alias.bool,
        #             # augend.constant.new({ elements = { "True", "False" }, word = true, cyclic = true }),
        #           },
        #           markdown = {
        #             augend.constant.new({ elements = { "[ ]", "[x]" }, word = false, cyclic = true }),
        #             augend.misc.alias.markdown_header,
        #           },
        #         },
        #       }
        #
        #       for name, group in pairs(dial_config.groups) do
        #         if name ~= "default" then
        #           vim.list_extend(group, dial_config.groups.default)
        #         end
        #       end
        #
        #       require("dial.config").augends:register_group(dial_config.groups)
        #       vim.g.dials_by_ft = dial_config.dials_by_ft
        #
        #       function _G.dial(increment, g)
        #         local mode = vim.fn.mode(true)
        #         local is_visual = mode == "v" or mode == "V" or mode == "\22"
        #         local func = (increment and "inc" or "dec") .. (g and "_g" or "_") .. (is_visual and "visual" or "normal")
        #         local group = vim.g.dials_by_ft[vim.bo.filetype] or "default"
        #         return require("dial.map")[func](group)
        #       end
        #     '';
        #   };
        # };

        searchCase = "smart";
        undoFile.enable = true;
        options = {
          expandtab = true;
          shiftwidth = 2;
          tabstop = 2;
          softtabstop = 2;
          scrolloff = 8;
          gdefault = true;
          # listchars = "tab:⊳ ,trail:·";
          # virtualedit = "block,onemore";
          # startofline = false;
          # wrap = true;
          # linebreak = true;
          breakindent = true;
          breakindentopt = "shift:2";
          confirm = true;
          # backupcopy = "yes";
          # conceallevel = 0;
        };

        # ----------------------------------------------------
        # Keymaps
        # ----------------------------------------------------
        keymaps = [
          {
            mode = ["n" "v"];
            key = "ä";
            action = "<cmd>q<cr>";
            desc = "quit";
          }
          {
            mode = ["n" "v"];
            key = "ö";
            action = "<cmd>update<cr>";
            desc = "save";
          }
          {
            mode = ["n" "v"];
            key = "ü";
            action = "<cmd>bdelete<cr>";
            desc = "Delete Buffer";
          }
          {
            mode = ["n" "v"];
            key = "<leader>ü";
            action = "<cmd>lua delete_other_buffers()<cr>";
            desc = "Delete Other Buffers";
          }

          {
            mode = ["n" "v"];
            key = "l";
            action = "<cmd>bnext<cr>";
            desc = "next buffer";
          }
          {
            mode = ["n" "v"];
            key = "L";
            action = "<cmd>bprev<cr>";
            desc = "prev buffer";
          }

          {
            mode = "n";
            key = "<leader>vh";
            action = "<cmd>edit ~/nixos/home.nix<cr>";
            desc = "edit home.nix";
          }
          {
            mode = "n";
            key = "<leader>vn";
            action = "<cmd>edit ~/nixos/configuration.nix<cr>";
            desc = "edit configuration.nix";
          }
          {
            mode = "n";
            key = "<leader>vt";
            action = "<cmd>edit ~/MEGAsync/notes/todo.md<cr>";
            desc = "edit todo.md";
          }

          {
            mode = "n";
            key = "<leader>e";
            action = "<cmd>FzfLua files<cr>";
            desc = "Find Files";
          }
          {
            mode = "n";
            key = "<leader>a";
            action = "<cmd>FzfLua live_grep<cr>";
            desc = "Live Grep";
          }
          # {
          #   mode = "n";
          #   key = "<leader>A";
          #   action = "<cmd>Telescope grep_string<cr>";
          #   desc = "Grep Word Under Cursor";
          # }
          {
            mode = "n";
            key = "<leader>vr";
            action = "<cmd>FzfLua oldfiles<cr>";
            desc = "Recent Files";
          }

          {
            mode = "v";
            key = ">";
            action = ">gv";
            desc = "keep selection when indenting";
          }
          {
            mode = "v";
            key = "<";
            action = "<gv";
            desc = "keep selection when indenting";
          }
          {
            mode = "v";
            key = "=";
            action = "=gv";
            desc = "keep selection when indenting";
          }

          {
            mode = ["n" "v"];
            key = "Λ";
            action = "<C-W>k";
            desc = "focus window up";
          }
          {
            mode = ["n" "v"];
            key = "∀";
            action = "<C-W>j";
            desc = "focus window down";
          }
          {
            mode = ["n" "v"];
            key = "∫";
            action = "<C-W>h";
            desc = "focus window left";
          }
          {
            mode = ["n" "v"];
            key = "∃";
            action = "<C-W>l";
            desc = "focus window right";
          }
          {
            mode = ["n" "v"];
            key = "Φ";
            action = "<C-W>_";
            desc = "maximize window";
          }
          {
            mode = ["n" "v"];
            key = "∂";
            action = "<cmd>ToggleTerm direction=horizontal start_in_insert=true<cr>";
            desc = "open terminal";
          }

          {
            mode = "n";
            key = "h";
            action = "<cmd>let @/ = expand('<cword>')<cr>:set hls<cr>";
            desc = "highlight word under cursor";
          }
          {
            mode = "n";
            key = "<leader>/";
            action = "<cmd>nohls<cr>";
            desc = "clear search highlight";
          }

          {
            mode = "n";
            key = "Y";
            action = "y$";
            desc = "yank till end of line";
          }
          {
            mode = "n";
            key = "<leader>p";
            action = "v$<Left>pgvy";
            desc = "paste over rest of line";
          }
          {
            mode = "v";
            key = "p";
            action = "pgvy";
            desc = "keep clipboard when pasting over selection";
          }

          {
            mode = ["n" "v"];
            key = "<leader>gs";
            action = "<cmd>nohlsearch<CR><cmd>term tig status<CR>i";
            desc = "launch tig status";
          }
          {
            mode = ["n" "v"];
            key = "ß";
            action = "@q";
            desc = "run macro 'q'";
          }

          {
            mode = "n";
            key = "<leader>,";
            action = "<cmd>lua toggle_char_at_eol(',')<cr>";
            desc = "toggle , at end of line";
          }
          {
            mode = "n";
            key = "<leader>;";
            action = "<cmd>lua toggle_char_at_eol(';')<cr>";
            desc = "toggle ; at end of line";
          }

          {
            mode = "n";
            key = "<a-cr>";
            action = "<cmd>lua vim.lsp.buf.code_action()<cr>";
            desc = "Code Actions";
          }
          {
            mode = "n";
            key = "gd";
            action = "<cmd>lua smart_goto_definition()<cr>";
            desc = "Go to Definition (LSP or local)";
          }
          {
            mode = "n";
            key = "<leader>n";
            action = "<cmd>lua smart_diagnostic_goto()<cr>";
            desc = "Jump to next LSP diagnostic";
          }
          {
            mode = "n";
            key = "<leader>o";
            action = "<cmd>Neotree toggle<cr>";
            desc = "Toggle Neotree";
          }
        ];

        luaConfigRC.keymaps = lib.mkBefore ''
          -- Smart Home
          vim.keymap.set("n", "<Home>", function()
            return vim.fn.col(".") == vim.fn.match(vim.fn.getline("."), "\\S") + 1 and "<Home>" or "^"
          end, { expr = true })
          vim.keymap.set("i", "<Home>", function()
            return vim.fn.col(".") == vim.fn.match(vim.fn.getline("."), "\\S") + 1 and "<Home>" or "<C-O>^"
          end, { expr = true })

          -- Toggle a specific character at the end of the current line
          function toggle_char_at_eol(target_char)
            local line_content = vim.api.nvim_get_current_line()
            if line_content:sub(-1) == target_char then
              vim.api.nvim_set_current_line(line_content:sub(1, -2))
            else
              vim.api.nvim_set_current_line(line_content .. target_char)
            end
          end

          function delete_other_buffers()
            local current_buf = vim.api.nvim_get_current_buf()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if buf ~= current_buf and vim.api.nvim_buf_is_loaded(buf) then
                vim.api.nvim_buf_delete(buf, { force = false })
              end
            end
          end

          function smart_diagnostic_goto()
            local has_errors = next(vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })) ~= nil
            if has_errors then
              vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR, float = true })
            else
              local has_warnings = next(vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })) ~= nil
              if has_warnings then
                vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.WARN, float = true })
              else
                vim.diagnostic.goto_next({ float = true })
              end
            end
          end

          function smart_goto_definition()
            local clients = vim.lsp.get_clients({ bufnr = 0 })
            if next(clients) ~= nil then
              vim.lsp.buf.definition()
            else
              vim.cmd('normal! gd')
            end
          end
        '';
      };
    };
  };
}
