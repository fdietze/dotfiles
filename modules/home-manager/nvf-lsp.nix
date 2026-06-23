# nvf LSP + language layer: the heavy (~1.5 GiB) opt-in part of the Neovim
# config. Adds language servers, formatters, and treesitter grammars on top of
# the featherweight editor in nvf.nix. Imported only by hosts wanting the full
# dev toolchain (gurke, cubie); the base editor + all keymaps live in nvf.nix and
# arrive via profiles/shell-core.nix on every host.
#
# The nvf module itself is imported by nvf.nix; this file only adds settings, so
# any host importing nvf-lsp.nix must also import nvf.nix (true for all consumers
# via shell-core). The lsp-referencing keymaps/lua stay in nvf.nix and degrade to
# built-in fallbacks when no server is attached, so this layer is purely additive.
# See docs/superpowers/specs/2026-06-23-nvf-base-lsp-split-design.md
{lib, ...}: {
  programs.nvf.settings.vim = {
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
      # enableExtraDiagnostics = true;

      nix.enable = true;
      typescript.enable = true;
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
        enable = false;
        format.enable = false;
      };
      css.enable = true;
      html.enable = false;
    };

    # Auto-fetch missing flake inputs in nil LSP instead of prompting.
    # See https://github.com/oxalica/nil/blob/main/docs/configuration.md
    luaConfigRC.nilSettings = lib.mkAfter ''
      vim.lsp.config("nil", {
        settings = {
          ["nil"] = {
            nix = {
              -- Raise the eval heap cap (default 2560 MiB) so cross-input
              -- evaluation of home-manager+nixpkgs does not hit the limit
              -- and SIGABRT the nix subprocess. Kept finite (not null) to
              -- still abort cleanly instead of OOMing the whole machine.
              maxMemoryMB = 8192,
              flake = {
                autoArchive = true,
                autoEvalInputs = true,
              },
            },
          },
        },
      })
    '';
  };
}
