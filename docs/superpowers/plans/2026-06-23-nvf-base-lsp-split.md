# nvf Base/LSP Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `nvf.nix` a featherweight base editor imported by `shell-core` (so every host gets a working `nvim`/aliases), and move the 1.5 GiB LSP layer into an opt-in `nvf-lsp.nix`.

**Architecture:** Two home-manager modules both contributing to `programs.nvf.settings.vim.*`; home-manager merges disjoint attrs. `nvf.nix` (base) imports the nvf module and is imported by `profiles/shell-core.nix`. `nvf-lsp.nix` adds `lsp` + `languages` + nil settings and is imported only by hosts wanting the full dev toolchain (gurke, cubie).

**Tech Stack:** Nix, home-manager, NixOS, [nvf](https://nvf.notashelf.dev/options.html).

## Global Constraints

- Source of truth is the NixOS/home-manager config; verify with builds, never activate (`nixos-rebuild build` OK; never `nrs`/`switch`).
- Refactor invariant: hosts that already have full nvf (gurke, cubie) must produce **byte-identical** generations after the split — verify with `nvd diff`.
- `nvf`/`theme` specialArgs already reach every shell-core consumer (flake.nix:178-239, korken.nix:188) — no plumbing changes needed.
- Darwin (Le-Big-Mac, aarch64-darwin) cannot be built on the linux dev box; verify it by evaluation (`nix flake check` / `nix eval` of the activationPackage drvPath) and hand the actual build to the user on the Mac.
- Spec: `docs/superpowers/specs/2026-06-23-nvf-base-lsp-split-design.md`.

---

### Task 1: Guard the theme-retint systemd service for Linux-only

**Files:**
- Modify: `modules/home-manager/nvf.nix` (the `systemd.user.services."nvim-theme-${theme}"` block near the end, ~line 698)

**Interfaces:**
- Consumes: nothing.
- Produces: `nvf.nix` base that evaluates on aarch64-darwin (no systemd user services).

- [ ] **Step 1: Capture the current gurke generation for the invariant check**

```bash
cd ~/projects/dotfiles
nixos-rebuild build --flake .#gurke && cp -L result /tmp/gurke-before
```
Expected: build succeeds, `/tmp/gurke-before` symlink target captured.

- [ ] **Step 2: Wrap the systemd service in a Linux guard**

In `modules/home-manager/nvf.nix`, find:

```nix
  systemd.user.services."nvim-theme-${theme}" = let
```

Wrap the whole `systemd.user.services."nvim-theme-${theme}" = …;` assignment so it only applies on Linux. Change the binding to:

```nix
  systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    "nvim-theme-${theme}" = let
```

and close the extra brace at the end of that block (the existing `};` that closed the service attr now needs one more `};` to close the `mkIf`). Verify brace balance by eye — the block ends with `Install.WantedBy = [currentThemeTarget];` then `};` (service) then the new `};` (mkIf).

- [ ] **Step 3: Verify gurke generation is unchanged**

```bash
cd ~/projects/dotfiles
nixos-rebuild build --flake .#gurke
nvd diff /tmp/gurke-before result
```
Expected: `nvd` reports **no differences** (Linux still gets the service; the guard is a no-op on Linux).

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/nvf.nix
git commit -m "nvf: guard theme-retint systemd service for linux-only (darwin compat)"
```

---

### Task 2: Extract the LSP layer into `nvf-lsp.nix`

**Files:**
- Create: `modules/home-manager/nvf-lsp.nix`
- Modify: `modules/home-manager/nvf.nix` (remove `lsp` block, `languages` block, `luaConfigRC.nilSettings`)
- Modify: `hosts-nixos/gurke/home.nix` (add `nvf-lsp.nix` import alongside existing `nvf.nix`)
- Modify: `hosts-home/cubie.nix` (add `nvf-lsp.nix` import alongside existing `nvf.nix`)

**Interfaces:**
- Consumes: `nvf.homeManagerModules.default` (imported by `nvf.nix`; must be imported once in the final config — guaranteed because every host that imports `nvf-lsp.nix` also imports `nvf.nix`).
- Produces: `nvf-lsp.nix` setting `programs.nvf.settings.vim.lsp`, `…vim.languages`, `…vim.luaConfigRC.nilSettings`.

- [ ] **Step 1: Create `modules/home-manager/nvf-lsp.nix`**

Move the three blocks out of `nvf.nix` verbatim. The file:

```nix
# nvf LSP + language layer: the heavy (~1.5 GiB) opt-in part of the Neovim
# config. Adds language servers, formatters, and treesitter grammars on top of
# the featherweight editor in nvf.nix. Imported only by hosts wanting the full
# dev toolchain (gurke, cubie); base editor + all keymaps live in nvf.nix and
# arrive via profiles/shell-core.nix on every host.
#
# nvf module itself is imported by nvf.nix; this file only adds settings, so any
# host importing nvf-lsp.nix must also import nvf.nix (true for all consumers via
# shell-core). See docs/superpowers/specs/2026-06-23-nvf-base-lsp-split-design.md
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
```

Match the moved text **verbatim** against the current `nvf.nix` contents (copy from there, do not retype the lua).

- [ ] **Step 2: Remove the three blocks from `nvf.nix`**

Delete from `modules/home-manager/nvf.nix`:
- the entire `lsp = { … };` block (the one under `programs.nvf.settings.vim`, ~lines 53-64),
- the entire `languages = { … };` block (~lines 66-90),
- the entire `luaConfigRC.nilSettings = lib.mkAfter '' … '';` block (~lines 557-578).

Leave everything else (editor plugins, statusline, keymaps incl. the `vim.lsp.*`/`vim.diagnostic.*` keymaps, `luaConfigRC.keymaps`, `luaConfigRC.noctaliaTheme`, lua functions) untouched.

- [ ] **Step 3: Add `nvf-lsp.nix` import to gurke and cubie**

In `hosts-nixos/gurke/home.nix`, in the `imports` list, right after the `nvf.nix` line:

```nix
    ../../modules/home-manager/nvf.nix
    ../../modules/home-manager/nvf-lsp.nix
```

In `hosts-home/cubie.nix`, after its `nvf.nix` import:

```nix
    ../modules/home-manager/nvf.nix
    ../modules/home-manager/nvf-lsp.nix
```

- [ ] **Step 4: Verify gurke and cubie are byte-identical to before the split**

```bash
cd ~/projects/dotfiles
nixos-rebuild build --flake .#gurke
nvd diff /tmp/gurke-before result
nix build .#homeConfigurations.cubie.activationPackage -o /tmp/cubie-after
```
Expected: `nvd diff` for gurke reports **no differences** (same plugins/servers, just reorganized across two files). cubie build succeeds.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/nvf-lsp.nix modules/home-manager/nvf.nix hosts-nixos/gurke/home.nix hosts-home/cubie.nix
git commit -m "nvf: extract lsp+languages layer into nvf-lsp.nix (gurke/cubie opt in)"
```

---

### Task 3: Move the base editor into `shell-core`; drop direct nvf.nix imports

**Files:**
- Modify: `modules/home-manager/profiles/shell-core.nix` (add `../nvf.nix` import)
- Modify: `hosts-nixos/gurke/home.nix` (remove direct `nvf.nix` import — now via shell-core/shared)
- Modify: `hosts-home/cubie.nix` (remove direct `nvf.nix` import — now via shell-core)

**Interfaces:**
- Consumes: `nvf-lsp.nix` (gurke/cubie keep importing it for the heavy layer).
- Produces: every shell-core host (gurke, cubie, template, Le-Big-Mac, korken) has the base editor.

- [ ] **Step 1: Add `nvf.nix` to shell-core imports**

In `modules/home-manager/profiles/shell-core.nix`, add to the `imports` list (it already imports `../shell.nix`, `../dotfiles.nix`, etc.):

```nix
    ../shell.nix
    ../nvf.nix
```

Update the existing comment in that imports block if it claims nvf is per-host (the `# ai-agents is intentionally NOT here…` comment stays; nvf now IS here).

- [ ] **Step 2: Remove the now-redundant direct nvf.nix imports**

In `hosts-nixos/gurke/home.nix`, remove the line:

```nix
    ../../modules/home-manager/nvf.nix
```
(keep `../../modules/home-manager/nvf-lsp.nix`). Update the adjacent `# NVF Neovim configuration explicitly enabled for this host.` comment to note the base now comes via shell-core and only the LSP layer is host-opted.

In `hosts-home/cubie.nix`, remove its `../modules/home-manager/nvf.nix` line (keep `nvf-lsp.nix`). Update the comment block above it accordingly.

- [ ] **Step 3: Verify the LSP hosts are still identical and base hosts now have nvim**

```bash
cd ~/projects/dotfiles
nixos-rebuild build --flake .#gurke
nvd diff /tmp/gurke-before result
nix build .#homeConfigurations.cubie.activationPackage -o /tmp/cubie-after2
nvd diff /tmp/cubie-after /tmp/cubie-after2
# korken (nix-on-droid) + template (nixos) must now contain nvim:
nix build .#nixOnDroidConfigurations.korken.activationPackage -o /tmp/korken-after 2>/dev/null \
  || nix eval --raw .#nixOnDroidConfigurations.korken.config.home-manager.config.home.activationPackage.drvPath
ls -l /tmp/korken-after/home-path/bin/nvim 2>/dev/null || echo "check korken closure for nvim"
```
Expected: gurke and cubie `nvd diff` report **no differences** (base just moved import location). korken/template builds gain `nvim` in their closure.

- [ ] **Step 4: Verify Le-Big-Mac (darwin) evaluates with nvim and no LSP**

```bash
cd ~/projects/dotfiles
# Eval-only (cannot build aarch64-darwin on linux): confirm it evaluates and
# the closure references neovim but NOT the heavy servers.
nix eval --raw .#homeConfigurations.Le-Big-Mac.activationPackage.drvPath
```
Expected: a drv path prints (evaluation succeeds — proves the systemd guard works and base editor is present). Note in the commit/PR that the actual build + `nvim`/`v`/`vg` smoke test must run on the Mac (`home-manager switch -b backup --flake ~/projects/dotfiles#Le-Big-Mac`), and that no `rust-analyzer`/`nil` source-builds should occur.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/shell-core.nix hosts-nixos/gurke/home.nix hosts-home/cubie.nix
git commit -m "shell-core: provide nvf base editor on every host; drop direct nvf imports"
```

---

## Self-Review

- **Spec coverage:** two modules (Task 2) ✓; base in shell-core (Task 3) ✓; gurke/cubie keep LSP (Task 2-3) ✓; Le-Big-Mac/korken/template base-only (Task 3) ✓; darwin systemd guard (Task 1) ✓; treesitter rides with LSP layer — it's inside the moved `languages` block (Task 2) ✓; nvd-identical invariant (Tasks 1-3) ✓.
- **Placeholder scan:** none — all moved code is the verbatim existing config; commands are exact.
- **Type consistency:** module option paths consistent (`programs.nvf.settings.vim.{lsp,languages,luaConfigRC.nilSettings}`); import paths use correct relative depth (`../` from profiles, `../../` from hosts-nixos, `../` from hosts-home).

## Verification (whole-plan, post-Task-3)

- gurke + cubie: `nvd diff` against pre-split = no change.
- Le-Big-Mac: evaluates; build + live `nvim`/`v`/`vg`/`vr`/`gd` smoke test on the Mac; confirm no rust source-builds.
- korken/template: closure contains `nvim`; aliases resolve.
