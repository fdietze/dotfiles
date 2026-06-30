# Unified host commands (`switch` / `pull` / `upgrade`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every host (nixos / standalone-home / nix-on-droid) the same three commands — `switch`, `pull`, `upgrade` — each backed by the correct activation mechanism for its category.

**Architecture:** A single home-manager module `modules/home-manager/host-commands.nix`, imported by the universal `shell-core.nix`, dispatches the `switch` backend on a new `hostType` special arg. `pull` and `upgrade` are category-agnostic wrappers that call the local `switch`. The existing nixos-only `nrs` machinery moves into this module's nixos branch and gains an exit code.

**Tech Stack:** Nix (flakes, home-manager, nixos, nix-on-droid), bash (`pkgs.writeShellScriptBin`), tmux, systemd-run.

## Global Constraints

- Repo: `/home/felix/projects/dotfiles`, git branch `master`. The working tree has unrelated dirty files (`flake.lock`, `home/noctalia/settings.toml`, `hosts-home/cubie.nix`) — **never stage them**; each task stages only its own files by explicit path.
- Spec: `docs/superpowers/specs/2026-06-24-host-switch-pull-upgrade-design.md`.
- Option namespace in home-manager is `my.*` (e.g. `my.devLinks` in `dev-links.nix`). The nixos `my.*` (in `modules/options.nix`) is a *separate* tree — do not touch it.
- Never run `nrs`, `nixos-rebuild switch`, `nrb`, or any system-activating rebuild. Verification uses **build/eval only** (`nixos-rebuild build`, `nix build … toplevel`, `nix eval … drvPath`).
- The machine running this is the x86_64 nixos host `gurke`; `cubie` (aarch64) and `korken` (aarch64 droid) and `Le-Big-Mac` (aarch64-darwin) cannot be *built* here, only **eval**'d.
- Move code between files with shell commands (verbatim), not retyping.
- Commit each task separately, staging only that task's paths.

---

### Task 1: Single source for the repo path — `my.dotfilesDir`

Introduce one home-manager option for the dotfiles directory and route every hardcoded `projects/dotfiles` reference through it. Pure refactor: the option default equals the old literal, so build output must be byte-identical.

**Files:**
- Create: `modules/home-manager/dotfiles-dir.nix`
- Modify: `modules/home-manager/profiles/shell-core.nix` (import + `repoDir` let at line 16; aliases at lines 78, 123–126)
- Modify: `modules/home-manager/dotfiles.nix:8`
- Modify: `modules/home-manager/dev-links.nix:13`
- Modify: `modules/home-manager/desktops/noctalia-niri.nix:9`
- Modify: `modules/home-manager/shell.nix:213`
- Modify: `modules/home-manager/nvf.nix:340,346`

**Interfaces:**
- Produces: option `my.dotfilesDir` (type `str`, default `${config.home.homeDirectory}/projects/dotfiles`), read everywhere as `config.my.dotfilesDir`.

- [ ] **Step 1: Build the baseline toplevel (before any change)**

```bash
cd /home/felix/projects/dotfiles
nixos-rebuild build --flake .#gurke && cp -L result /tmp/host-cmd-before || \
  nix build .#nixosConfigurations.gurke.config.system.build.toplevel -o /tmp/host-cmd-before
```
Expected: a `/tmp/host-cmd-before` symlink to a system toplevel store path.

- [ ] **Step 2: Create the option module**

`modules/home-manager/dotfiles-dir.nix`:
```nix
# Single source for the dotfiles checkout path. Anticipates moving the repo out
# of ~/projects: change the default here, every consumer follows. Home-manager
# `my.*` tree (separate from the nixos `my.*` in modules/options.nix).
{
  config,
  lib,
  ...
}: {
  options.my.dotfilesDir = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/projects/dotfiles";
    description = "Absolute path to the dotfiles git checkout on this host.";
  };
}
```

- [ ] **Step 3: Import the option module from shell-core and point `repoDir` at it**

In `modules/home-manager/profiles/shell-core.nix`, add the import (inside the existing `imports = [ … ];`, after `../dotfiles.nix`):
```nix
    ../dotfiles.nix
    ../dotfiles-dir.nix
```
Replace the `repoDir` let (line 16):
```nix
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";
```
with:
```nix
  repoDir = config.my.dotfilesDir;
```

- [ ] **Step 4: Migrate the editor aliases to `repoDir`**

In the same file, replace the five alias lines:
```nix
    vf = ''$EDITOR "$HOME"/projects/dotfiles/flake.nix'';
```
→
```nix
    vf = ''$EDITOR ${repoDir}/flake.nix'';
```
and:
```nix
    vv = ''$EDITOR "$HOME"/projects/dotfiles/modules/home-manager/nvf.nix'';
    vn = ''$EDITOR "$HOME"/projects/dotfiles/hosts-nixos/gurke/default.nix'';
    vh = ''$EDITOR "$HOME"/projects/dotfiles/hosts-nixos/gurke/home.nix'';
    vp = ''$EDITOR "$HOME"/projects/dotfiles/modules/home-manager/packages.nix'';
```
→
```nix
    vv = ''$EDITOR ${repoDir}/modules/home-manager/nvf.nix'';
    vn = ''$EDITOR ${repoDir}/hosts-nixos/gurke/default.nix'';
    vh = ''$EDITOR ${repoDir}/hosts-nixos/gurke/home.nix'';
    vp = ''$EDITOR ${repoDir}/modules/home-manager/packages.nix'';
```

- [ ] **Step 5: Point the other `repoDir` lets at the option**

In each of `modules/home-manager/dotfiles.nix:8`, `modules/home-manager/dev-links.nix:13`, `modules/home-manager/desktops/noctalia-niri.nix:9`, replace:
```nix
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";
```
with:
```nix
  repoDir = config.my.dotfilesDir;
```

- [ ] **Step 6: Migrate the remaining literal references**

`modules/home-manager/shell.nix:213` — replace:
```
        commits=$($HOME/projects/dotfiles/home/bin/git-select-commit)
```
with (interpolate the nix string into the shell script):
```
        commits=$(${config.my.dotfilesDir}/home/bin/git-select-commit)
```

`modules/home-manager/nvf.nix` lines 340 and 346 — replace:
```nix
            action = "<cmd>edit ~/projects/dotfiles/hosts-nixos/gurke/home.nix<cr>";
            action = "<cmd>edit ~/projects/dotfiles/hosts-nixos/gurke/default.nix<cr>";
```
with:
```nix
            action = "<cmd>edit ${config.my.dotfilesDir}/hosts-nixos/gurke/home.nix<cr>";
            action = "<cmd>edit ${config.my.dotfilesDir}/hosts-nixos/gurke/default.nix<cr>";
```
**`nvf.nix` has no `config` arg** — add it. Change the module header from:
```nix
{
  lib,
  pkgs,
  nvf,
  theme,
  ...
}: let
```
to:
```nix
{
  config,
  lib,
  pkgs,
  nvf,
  theme,
  ...
}: let
```

- [ ] **Step 7: Verify no `projects/dotfiles` literals remain in nix code (except host-file comments)**

Run:
```bash
cd /home/felix/projects/dotfiles
rg -n "projects/dotfiles" --type nix
```
Expected: only the comment lines in `hosts-home/cubie.nix` and `hosts-home/Le-Big-Mac.nix` (handled in Task 5). No code references.

- [ ] **Step 8: Build after the change and diff with nvd (must be empty)**

```bash
cd /home/felix/projects/dotfiles
nixos-rebuild build --flake .#gurke && cp -L result /tmp/host-cmd-after || \
  nix build .#nixosConfigurations.gurke.config.system.build.toplevel -o /tmp/host-cmd-after
nix run nixpkgs#nvd -- diff /tmp/host-cmd-before /tmp/host-cmd-after
```
Expected: `nvd` reports **no version/package changes** (`<<< … >>>` empty, "0 added, 0 removed, 0 changed" or equivalent). If anything changed, a literal was not byte-equal — re-check the migration.

- [ ] **Step 9: Commit**

```bash
cd /home/felix/projects/dotfiles
git add modules/home-manager/dotfiles-dir.nix \
        modules/home-manager/profiles/shell-core.nix \
        modules/home-manager/dotfiles.nix \
        modules/home-manager/dev-links.nix \
        modules/home-manager/desktops/noctalia-niri.nix \
        modules/home-manager/shell.nix \
        modules/home-manager/nvf.nix
git commit -m "refactor(home): single source my.dotfilesDir for repo path"
```

---

### Task 2: Plumb `hostType` (and `hostLabel` on `mkHome`) through the flake

Each builder injects the host category so `host-commands.nix` can dispatch.

**Files:**
- Modify: `flake.nix` (`mkHost` specialArgs; `mkHome`, `mkHomeHost`, `mkNixOnDroid` extraSpecialArgs)

**Interfaces:**
- Produces: special arg `hostType ∈ {"nixos","home","droid"}` available to all modules of each config; `hostLabel` present for every home/droid config (`mkHome` gains `hostLabel = "felix@${system}"`).

- [ ] **Step 1: Add `hostType = "nixos"` to `mkHost`**

In `flake.nix`, inside `mkHost`'s `specialArgs = { … }`, add a line next to `flake-inputs = inputs;`:
```nix
        specialArgs = {
          flake-inputs = inputs;
          hostType = "nixos";
          inherit hostLocal;
          uiFonts = uiFontsFor system;
        };
```

- [ ] **Step 2: Add `hostType` + `hostLabel` to `mkHome`**

In `mkHome`'s `extraSpecialArgs = { … }`, add:
```nix
        extraSpecialArgs = {
          flake-inputs = inputs;
          hostType = "home";
          hostLabel = "felix@${system}";
          nvf = nvf;
          theme = defaultTheme;
          uiFonts = uiFontsFor system;
        };
```

- [ ] **Step 3: Add `hostType = "home"` to `mkHomeHost`**

In `mkHomeHost`'s `extraSpecialArgs`, add `hostType = "home";` next to `flake-inputs = inputs;` (it already passes `hostLabel = name;`).

- [ ] **Step 4: Add `hostType = "droid"` to `mkNixOnDroid`**

In `mkNixOnDroid`'s `extraSpecialArgs`, add `hostType = "droid";` next to `flake-inputs = inputs;` (it already passes `hostLabel = deviceName;`).

- [ ] **Step 5: Verify all four config kinds still evaluate**

```bash
cd /home/felix/projects/dotfiles
nix eval --impure .#nixosConfigurations.gurke.config.system.build.toplevel.drvPath
nix eval --impure .#homeConfigurations.cubie.activationPackage.drvPath
nix eval --impure '.#homeConfigurations."felix@x86_64-linux".activationPackage.drvPath'
nix eval --impure .#nixOnDroidConfigurations.korken.activationPackage.drvPath
```
Expected: each prints a `/nix/store/….drv` path, no eval errors. (A non-fatal *realize* failure for korken's CI-built proot is fine — only the eval matters.)

- [ ] **Step 6: Commit**

```bash
cd /home/felix/projects/dotfiles
git add flake.nix
git commit -m "feat(flake): inject hostType (and hostLabel on mkHome) per builder"
```

---

### Task 3: Relocate `nrs` → `switch` into `host-commands.nix`, with exit-code propagation (Change X)

Move the nixos rebuild machinery out of `theme-switching.nix` into a new universal module, rename the binary to `switch`, and make it return the rebuild's exit code. After this task, `switch` (and `nrs` no longer) exists on nixos and behaves exactly like the old `nrs` plus a propagated rc.

**Files:**
- Create: `modules/home-manager/host-commands.nix`
- Modify: `modules/home-manager/theme-switching.nix` (remove moved bindings + `nrsScript` from `home.packages`)
- Modify: `modules/home-manager/profiles/shell-core.nix` (import host-commands; remove `nrs = "nrs";` alias at line 128)

**Interfaces:**
- Consumes: `hostType`, `hostLabel ? null` (Task 2); `config.my.dotfilesDir` (Task 1); `pkgs`, `lib`.
- Produces: a `pkgs.writeShellScriptBin "switch"` on nixos hosts, added to `home.packages`. The script writes its rebuild rc to `$XDG_RUNTIME_DIR/nrs.rc` and exits with it. (Generic `pull`/`upgrade` come in Task 4.)

- [ ] **Step 1: Copy theme-switching.nix verbatim as the new module (preserve content)**

```bash
cd /home/felix/projects/dotfiles
cp modules/home-manager/theme-switching.nix modules/home-manager/host-commands.nix
```
(We will strip each file down to its responsibility in the next steps — copying verbatim first avoids retyping the long `nrs` script.)

- [ ] **Step 2: In `host-commands.nix`, keep only the switch machinery**

Edit `modules/home-manager/host-commands.nix` so it contains *only*: the `desktopRegistry`/`specToDesktop`/`specCaseArms`/`nrsTmuxConfig`/`nrsInner`/`nrsScript` let-bindings and a minimal module body. Concretely:
- Change the module header args to:
```nix
{
  lib,
  pkgs,
  config,
  hostType,
  hostLabel ? null,
  ...
}: let
  dotfilesDir = config.my.dotfilesDir;
  desktopRegistry = import ../desktop-registry.nix;
```
  (Drop the `desktop`, `theme` args and the `hasThemeVariants` / `switchToConfigurationPath` lets — those stay in `theme-switching.nix`.)
- Delete the `mkThemeSwitchScript` let-binding entirely (stays in theme-switching).
- Rename the `nrsScript` binding's binary from `"nrs"` to `"switch"`: change
```nix
  nrsScript = pkgs.writeShellScriptBin "nrs" ''
```
to
```nix
  nixosSwitch = pkgs.writeShellScriptBin "switch" ''
```
  (rename the *let name* to `nixosSwitch` and the binary name to `switch`; keep the script body for now — it is edited in Step 3).
- Replace the entire module body (`in { … }`) with:
```nix
in {
  home.packages = lib.optional (hostType == "nixos") nixosSwitch;
}
```

- [ ] **Step 3: Apply Change X — make `switch` return the rebuild rc**

In `host-commands.nix`, in the `nrsInner` script, right after the line `rc=$?` (which follows `"$@"`), add the rc-file write:
```bash
    "$@"
    rc=$?

    # Record the rebuild rc so the outer script (and pull/upgrade) can read it;
    # the outer process used to `exec tmux attach` and thus returned no code.
    printf '%s' "$rc" > "''${XDG_RUNTIME_DIR:-/tmp}/nrs.rc"
```
Then in the `nixosSwitch` script: (a) before launching tmux, clear any stale rc file — add immediately before the `${pkgs.systemd}/bin/systemd-run --user --scope --quiet \` line:
```bash
    rm -f "''${XDG_RUNTIME_DIR:-/tmp}/nrs.rc"
```
and (b) replace the final line:
```bash
    exec "''${TMUX[@]}" attach -t "$SESSION"
```
(the *last* occurrence, after the `systemd-run` block — not the one in the "already running" reattach branch) with:
```bash
    "''${TMUX[@]}" attach -t "$SESSION"
    exit "$(${pkgs.coreutils}/bin/cat "''${XDG_RUNTIME_DIR:-/tmp}/nrs.rc" 2>/dev/null || echo 0)"
```

- [ ] **Step 4: Strip the moved machinery out of `theme-switching.nix`**

In `modules/home-manager/theme-switching.nix`, delete the now-relocated let-bindings: `specToDesktop`, `specCaseArms`, `nrsTmuxConfig`, `nrsInner`, `nrsScript`. Keep: `desktopRegistry`, `hasThemeVariants`, `switchToConfigurationPath`, `mkThemeSwitchScript`. Then change `home.packages` from:
```nix
  home.packages =
    [
      nrsScript
    ]
    ++ lib.optionals hasThemeVariants [
      (mkThemeSwitchScript "light")
      (mkThemeSwitchScript "dark")
    ];
```
to:
```nix
  home.packages = lib.optionals hasThemeVariants [
    (mkThemeSwitchScript "light")
    (mkThemeSwitchScript "dark")
  ];
```
Leave the `desktop`/`theme` args, `home.file.".theme"`, and the `systemd.user.targets` block untouched.

- [ ] **Step 5: Wire host-commands into shell-core and drop the `nrs` alias**

In `modules/home-manager/profiles/shell-core.nix`, add to `imports` (after `../dotfiles-dir.nix` from Task 1):
```nix
    ../dotfiles-dir.nix
    ../host-commands.nix
```
Remove the alias line (line ~128):
```nix
    nrs = "nrs";
```

- [ ] **Step 6: Verify gurke builds and `switch` is present, `nrs` is gone**

```bash
cd /home/felix/projects/dotfiles
nixos-rebuild build --flake .#gurke
ls result/sw/bin/switch && ! ls result/sw/bin/nrs 2>/dev/null && echo "OK: switch present, nrs absent"
```
Expected: build succeeds; `switch` exists in the profile; `nrs` does not; prints `OK: …`.
Also confirm the rc plumbing is in the built script:
```bash
grep -q 'nrs.rc' result/sw/bin/switch && echo "OK: rc propagation present"
```

- [ ] **Step 7: Commit**

```bash
cd /home/felix/projects/dotfiles
git add modules/home-manager/host-commands.nix \
        modules/home-manager/theme-switching.nix \
        modules/home-manager/profiles/shell-core.nix
git commit -m "feat(home): relocate nrs to host-commands as 'switch' with exit code"
```

---

### Task 4: Add `pull`, `upgrade`, and home/droid `switch` dispatch

Make `host-commands.nix` emit all three commands for all categories: dispatch `switch` by `hostType`, and add the generic `pull`/`upgrade` wrappers.

**Files:**
- Modify: `modules/home-manager/host-commands.nix`

**Interfaces:**
- Consumes: `nixosSwitch` (Task 3), `hostType`, `hostLabel`, `dotfilesDir`, `pkgs`, `lib`.
- Produces: `pkgs.writeShellScriptBin` binaries `switch`, `pull`, `upgrade` on **every** host; `pull`/`upgrade` invoke `switch` by absolute store path.

- [ ] **Step 1: Add the dispatch + wrappers as let-bindings**

In `host-commands.nix`, after the `nixosSwitch` binding, add:
```nix
  # switch: apply the current checkout. Only this varies by host category.
  switchScript =
    if hostType == "nixos"
    then nixosSwitch
    else if hostType == "home"
    then
      pkgs.writeShellScriptBin "switch" ''
        set -euo pipefail
        exec home-manager switch -b backup --flake ${dotfilesDir}#${hostLabel} "$@"
      ''
    else if hostType == "droid"
    then
      pkgs.writeShellScriptBin "switch" ''
        set -euo pipefail
        exec nix-on-droid switch --flake ${dotfilesDir}#${hostLabel} "$@"
      ''
    else throw "host-commands: unknown hostType '${hostType}'";

  # pull: sync my latest committed config, then apply. Category-agnostic.
  # --rebase --autostash so a dirty working tree (mid-iteration) doesn't abort.
  pullScript = pkgs.writeShellScriptBin "pull" ''
    set -euo pipefail
    git -C ${dotfilesDir} pull --rebase --autostash
    exec ${switchScript}/bin/switch "$@"
  '';

  # upgrade: bump upstream inputs, then apply, then commit the lock — but only
  # after a successful switch (set -e gates it), proving the bump builds.
  # nice -n 18: the full rebuild is long; niceness is inherited through
  # sudo / systemd-run --scope down to the actual build. flake.lock is shared
  # by all hosts, so one host upgrades and the rest `pull` the committed lock.
  # Push stays manual.
  upgradeScript = pkgs.writeShellScriptBin "upgrade" ''
    set -euo pipefail
    cd ${dotfilesDir}
    nix flake update
    nice -n 18 ${switchScript}/bin/switch
    git -C ${dotfilesDir} diff --quiet flake.lock \
      || git -C ${dotfilesDir} commit flake.lock -m "flake.lock: update inputs"
  '';
```

- [ ] **Step 2: Replace the module body to install all three commands**

Change the body from:
```nix
in {
  home.packages = lib.optional (hostType == "nixos") nixosSwitch;
}
```
to:
```nix
in {
  home.packages = [
    switchScript
    pullScript
    upgradeScript
  ];
}
```

- [ ] **Step 3: Verify nixos build still works and all three commands exist**

```bash
cd /home/felix/projects/dotfiles
nixos-rebuild build --flake .#gurke
for c in switch pull upgrade; do ls result/sw/bin/$c >/dev/null && echo "OK $c"; done
```
Expected: build succeeds; prints `OK switch`, `OK pull`, `OK upgrade`.

- [ ] **Step 4: Verify home + droid configs eval and emit the right backend**

```bash
cd /home/felix/projects/dotfiles
nix eval --impure .#homeConfigurations.cubie.activationPackage.drvPath
nix eval --impure .#nixOnDroidConfigurations.korken.activationPackage.drvPath
nix eval --impure '.#homeConfigurations."felix@x86_64-linux".activationPackage.drvPath'
```
Expected: all print a `.drv` path with no eval error (confirms the `home`/`droid` branches and `hostLabel` interpolation are valid; `felix@x86_64-linux` confirms `mkHome`'s `hostLabel`).

- [ ] **Step 5: Commit**

```bash
cd /home/felix/projects/dotfiles
git add modules/home-manager/host-commands.nix
git commit -m "feat(home): add pull + upgrade and home/droid switch dispatch"
```

---

### Task 5: Remove the legacy `home/bin/upgrade` and refresh host comments

Delete the stale script that would shadow the new `upgrade` in PATH, and update the two host-file comments that still show the old switch invocation.

**Files:**
- Delete: `home/bin/upgrade`
- Modify: `hosts-home/cubie.nix:4,6`, `hosts-home/Le-Big-Mac.nix:7`

- [ ] **Step 1: Confirm nothing references the legacy script**

```bash
cd /home/felix/projects/dotfiles
rg -n "bin/upgrade|home/bin/upgrade" --type nix; echo "exit: $?"
```
Expected: no nix references (the new `upgrade` is a nix-built binary; the legacy file is only PATH-discovered via `home/bin` on `sessionPath`).

- [ ] **Step 2: Remove the legacy script**

```bash
cd /home/felix/projects/dotfiles
git rm home/bin/upgrade
```

- [ ] **Step 3: Update the host-file comments**

`hosts-home/cubie.nix` — replace the comment block referencing the manual switch:
```
# user). Standalone Home Manager; repo cloned under ~/projects/dotfiles,
```
keep as-is (path note is fine), and replace:
```
#   home-manager switch -b backup --flake ~/projects/dotfiles#cubie
```
with:
```
#   switch        # (or: home-manager switch -b backup --flake <dotfilesDir>#cubie)
```
`hosts-home/Le-Big-Mac.nix` — replace:
```
#   home-manager switch -b backup --flake ~/projects/dotfiles#Le-Big-Mac
```
with:
```
#   switch        # (or: home-manager switch -b backup --flake <dotfilesDir>#Le-Big-Mac)
```

- [ ] **Step 4: Verify the home configs still eval (comments only, sanity)**

```bash
cd /home/felix/projects/dotfiles
nix eval --impure .#homeConfigurations.cubie.activationPackage.drvPath
nix eval --impure '.#homeConfigurations."Le-Big-Mac".activationPackage.drvPath'
```
Expected: both print a `.drv` path.

- [ ] **Step 5: Commit**

```bash
cd /home/felix/projects/dotfiles
git add hosts-home/cubie.nix hosts-home/Le-Big-Mac.nix
git commit -m "chore: drop legacy home/bin/upgrade; refresh host switch comments"
```

---

## Self-Review

**Spec coverage:**
- 3 commands / decomposition (pull,upgrade call switch) → Task 4.
- `host-commands.nix` imported by shell-core, `hostType` dispatch → Tasks 3, 4.
- Change X (rc via `$XDG_RUNTIME_DIR/nrs.rc`) → Task 3 Step 3.
- nixos/home/droid switch backends → Task 4 Step 1.
- pull `--rebase --autostash` → Task 4 Step 1 (`pullScript`).
- upgrade: flake update → switch → commit lock after success, pathspec commit, manual push, `nice -n 18` → Task 4 Step 1 (`upgradeScript`).
- Plumbing `hostType` + `hostLabel` on mkHome → Task 2.
- Prereq `my.dotfilesDir`, 15 refs, nvd byte-identical → Task 1.
- Move nrs out of theme-switching; keep theme scripts → Task 3 Step 4.
- Remove `nrs = "nrs"` alias → Task 3 Step 5. `nrb` untouched (never referenced) ✓.
- `git rm home/bin/upgrade`, port only `nice` → Tasks 5, 4.

**Placeholder scan:** none — all code blocks concrete.

**Type/name consistency:** `nixosSwitch` (Task 3) consumed by `switchScript` (Task 4); `switchScript`/`pullScript`/`upgradeScript` defined and installed in Task 4; binaries all named `switch`/`pull`/`upgrade`; `dotfilesDir = config.my.dotfilesDir` (Task 3 header) used by Task 4 wrappers; `hostType`/`hostLabel` produced in Task 2, consumed in Tasks 3–4. Consistent.
