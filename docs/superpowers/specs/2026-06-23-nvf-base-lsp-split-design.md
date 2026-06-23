# nvf split: featherweight base editor + opt-in LSP layer

## Problem

`shell-core` defines editor aliases (`vim=nvim`, `v`/`vg`/`vr` → `nvim -c "FzfLua …"`,
`vf`/`vt`/`vv`/`vn`/`vh`/`vp`/`vb` → `$EDITOR`) but does **not** provide an editor.
The editor (`nvf.nix`) is imported per-host. Three shell-core hosts import it; three do not:

| host | imports nvf today | editor present |
|---|---|---|
| gurke, cubie | yes (direct) | ✅ |
| Le-Big-Mac, korken, template | no | ❌ broken aliases, no `$EDITOR` |

So every alias is broken on Le-Big-Mac (aarch64-darwin), korken (nix-on-droid,
aarch64-linux), and template. `template/default.nix:38` comment (*"shell-core (nvf)"*)
already assumes shell-core bundles the editor — it does not.

## Measurement (on cubie, aarch64-linux)

Full nvf closure = **1.5 GiB**, ~93% of which is the LSP layer:

| component | size | from |
|---|---|---|
| basedpyright (+bundled node) | 903 MiB | `python.enable` |
| vscode-langservers-extracted | 330 MiB | `json/css/html` |
| typescript-language-server + typescript | ~285 + 283 MiB | `typescript.enable` |
| rust-analyzer | 155 MiB | `rust.enable` |
| nil | 71 MiB | `nix.enable` |
| every lua plugin (editor, fzf, theme, neo-tree…) | <1 MiB each | the base |

The base editor is a rounding error; the entire 1.5 GiB is `lsp.enable` +
`languages.*.enable`. On aarch64-darwin (Le-Big-Mac) the rust servers
(`rust-analyzer`, `nil`) are a **source-build risk** — no binary cache, same problem
that made codex skipped on that host.

## Decision

Split `nvf.nix` into two home-manager modules and make the base universal:

- **`nvf.nix`** (base): neovim + all lua plugins (fzf-lua, blink-cmp, lualine,
  neo-tree, snacks, surround, toggler, theme), all keymaps, all lua functions.
  Imported by **`profiles/shell-core.nix`** → every shell-core host gets a working
  editor. Closure ≈ tens of MB, no source-builds.
- **`nvf-lsp.nix`** (opt-in heavy layer): the `lsp` block + `languages` block +
  `luaConfigRC.nilSettings`. The 1.5 GiB layer including treesitter grammars.
  Imported per-host where the full dev experience is wanted.

Both modules set `programs.nvf.settings.vim.*`; home-manager merges the disjoint
attrs. Only `nvf.nix` imports `nvf.homeManagerModules.default`.

### Why the cut is clean

The lsp-referencing keymaps/lua stay in **base** unchanged: `<a-cr>`
(`vim.lsp.buf.code_action`), `gd` (`smart_goto_definition`), `<leader>n`
(`smart_diagnostic_goto`) use **built-in** `vim.lsp.*` / `vim.diagnostic.*` APIs that
exist with zero language servers. `smart_goto_definition` explicitly falls back to
`normal! gd` when no client is attached. So they degrade gracefully — no keymap
partitioning needed. The cut is just the two contiguous blocks + nilSettings.

### Resolved sub-decisions

1. **Treesitter rides with the LSP layer.** `languages.<lang>.enable` bundles LSP
   server + treesitter grammar + formatter. Simplest cut moves the whole `languages`
   block to `nvf-lsp.nix`; base relies on vim's built-in syntax highlighting. KISS —
   avoids splitting the `languages` attrset and `mkForce` overrides, and keeps grammar
   weight off the phone/quick-edit hosts.
2. **korken stays base-only.** Resources (15 GiB RAM, 396 GB free) + cache allow full
   LSP, but it's a phone; opt into `nvf-lsp.nix` later if real editing happens there.
3. **Naming:** `nvf-lsp.nix` for the heavy layer.

## Migration

| host | change |
|---|---|
| `profiles/shell-core.nix` | add `import ../nvf.nix` |
| `hosts-nixos/gurke/home.nix` | replace direct `nvf.nix` import → `nvf-lsp.nix` |
| `hosts-home/cubie.nix` | replace direct `nvf.nix` import → `nvf-lsp.nix` |
| Le-Big-Mac, korken, template | no change — base arrives via shell-core, no LSP |

`nvf`/`theme` specialArgs already reach every shell-core consumer (flake.nix:178-239;
`korken.nix:188`), so moving the import into shell-core needs no plumbing changes.

### Darwin compatibility

`nvf.nix` (base) ends with `systemd.user.services."nvim-theme-${theme}"` (theme
retint). systemd user services don't exist on aarch64-darwin → wrap that block in
`lib.mkIf pkgs.stdenv.hostPlatform.isLinux`. The `home.file."bin/noctalia-retint-nvim"`
script is inert on darwin (never triggered) and can stay unguarded.

## Verification

- `nix flake check` / `home-manager build --flake .#Le-Big-Mac` (darwin: confirm no
  systemd assertion, editor present, no rust source-builds).
- `home-manager build` for gurke (NixOS), cubie, korken — confirm gurke/cubie still
  pull the LSP layer; korken/template/Le-Big-Mac base only.
- `nvd diff` base-vs-lsp generations to confirm the 1.5 GiB delta is exactly the LSP
  layer and the base closure is small.
- Live: on a base-only host, `nvim`, `v`, `vg`, `vr`, `gd` (falls back to `normal! gd`)
  all work; on an LSP host, language servers attach.

## Out of scope

- macOS sandbox for agents (separate follow-up noted in `Le-Big-Mac.nix`).
- Whether korken/Le-Big-Mac later opt into LSP — a one-line import when wanted.
