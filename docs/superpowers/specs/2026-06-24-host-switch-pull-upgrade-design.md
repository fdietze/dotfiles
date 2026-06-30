# Unified host commands: `switch` / `pull` / `upgrade`

Date: 2026-06-24

## Problem

Each host category in this repo activates configuration differently:

- `hosts-nixos/*` → `nixos-rebuild switch` (today wrapped by the nixos-only `nrs`
  in `modules/home-manager/theme-switching.nix`; tmux + specialisation aware)
- `hosts-home/*` → `home-manager switch -b backup --flake ~/projects/dotfiles#<host>`
- `hosts-nix-on-droid/*` → `nix-on-droid switch --flake ~/projects/dotfiles#<host>`

There is no consistent, self-documenting command set across categories, and no
standard "pull my latest committed config, then apply" or "bump upstream inputs,
then apply" command. The legacy `home/bin/upgrade` is stale (points at a dead
`$HOME/nixos` path, uses `nixos-rebuild boot`, mixes in imperative steps).

## Goal

Every host — regardless of category — exposes the same three commands with
identical names, each backed by the correct activation mechanism for that host:

- **`switch`** — apply the current checkout (no git, no lock change).
- **`pull`** — `git pull --rebase --autostash`, then `switch`. Sync *my* latest
  committed config (changes made on another machine). Horizontal axis.
- **`upgrade`** — `nix flake update`, then `switch`, then (on success) commit the
  bumped `flake.lock`. Bring in newer upstream inputs. Vertical axis.

These are three genuinely independent operations (apply / sync-mine /
upgrade-upstream). Naming uses full words as a semantic index; "update" is
deliberately avoided because nix already calls input bumps "flake update".

## Decomposition (SoC + DRY)

Only `switch` varies by host category. `pull` and `upgrade` are thin,
category-agnostic wrappers that call the local `switch`:

```
pull    = git -C <dir> pull --rebase --autostash && switch "$@"
upgrade = nix flake update (in <dir>) && switch \
          && git -C <dir> commit flake.lock -m "flake.lock: update inputs"
```

So the only per-category code is the `switch` backend dispatch.

## Architecture

### New module: `modules/home-manager/host-commands.nix`

Imported by `modules/home-manager/profiles/shell-core.nix` — the universal core
loaded by *all* categories (nixos via `home-manager.users.felix`, hosts-home via
`homeManagerConfiguration`, nix-on-droid via its home-manager integration). This
is why the module reaches every host. (`theme-switching.nix` is imported only by
`shared.nix`, i.e. nixos-desktop hosts — which is why `nrs` is nixos-only today.)

Dispatched by a new special arg **`hostType` ∈ {`nixos`, `home`, `droid`}**.

`switch` backend per `hostType`:

- **nixos** — the relocated `nrs` machinery (tmux server under `user@.service`
  via `systemd-run --user --scope`, upfront `sudo -v` + keepalive, optional
  `<specialisation>` arg, registry-driven `desktop_of` + relogin on desktop
  change). See prior art `2026-06-05-nrs-tmux-rewrite-design.md`. The switch
  script generation depends only on `desktop-registry.nix` (pure import), **not**
  on the `desktop`/`theme` args, so it evaluates fine on every host.
- **home** — `home-manager switch -b backup --flake <dotfilesDir>#<hostLabel>`
- **droid** — `nix-on-droid switch --flake <dotfilesDir>#<hostLabel>`

`pull` and `upgrade` are defined once, generically, calling `switch`.

`upgrade` applies `nice -n 18` to its `switch` invocation (long full rebuild;
niceness is inherited across fork/exec/sudo/`systemd-run --scope`, so it reaches
the actual build). `pull` is not niced (routine, smaller).

Module declares `hostLabel ? null` (nixos's `switch` does not use it).

### Change X — make `switch` return an exit code on nixos

The current `nrs` ends with `exec tmux attach`, replacing its own process, so it
returns no rc. `upgrade` needs `switch`'s success to gate the `flake.lock`
commit. Minimal fix:

- `nrsInner` (the in-tmux script) writes its rebuild rc to
  `$XDG_RUNTIME_DIR/nrs.rc`.
- The outer script does `tmux attach; exit "$(cat $XDG_RUNTIME_DIR/nrs.rc)"`
  instead of `exec tmux attach`.

`pull`/`upgrade` never pass a specialisation arg, so they re-apply the current
spec ⇒ `current_desktop == target_desktop` ⇒ the `loginctl terminate-user`
relogin branch cannot fire from them. The only missing piece is rc propagation.
home/droid already return rc natively (`home-manager` / `nix-on-droid switch`).

### Plumbing (`flake.nix`)

Each builder injects `hostType` into its (extra)specialArgs:

- `mkHost` → `hostType = "nixos"` (specialArgs)
- `mkHome` → `hostType = "home"`, plus add `hostLabel = "felix@${system}"`
  (it currently passes no `hostLabel`)
- `mkHomeHost` → `hostType = "home"` (already passes `hostLabel = name`)
- `mkNixOnDroid` → `hostType = "droid"` (already passes `hostLabel = deviceName`)

## Prerequisite refactor (separate commit, lands first)

Introduce a single source for the repo path, anticipating moving dotfiles out of
`~/projects`.

- New home-manager option **`my.dotfilesDir`**, default
  `${config.home.homeDirectory}/projects/dotfiles` (host-correct via
  `home.homeDirectory`; cubie's user differs). Lives in the existing `my.*`
  namespace alongside `my.desktop`/`my.theme`.
- Replace all 15 hardcoded references to `projects/dotfiles`:
  - collapse the 4 duplicated `repoDir = "${config.home.homeDirectory}/projects/dotfiles"`
    lets (`shell-core.nix`, `dotfiles.nix`, `dev-links.nix`,
    `desktops/noctalia-niri.nix`) into `config.my.dotfilesDir`
  - migrate the editor aliases' *base path* (`vf`/`vv`/`vn`/`vh`/`vp` in
    `shell-core.nix`); subpaths like `hosts-nixos/gurke/...` stay literal
  - `shell.nix` git-select-commit path, `nvf.nix` edit actions, host-file
    comments
- Verify byte-identical output with `nvd` (build before/after, diff shows no
  change). Commit before building the commands.

## Cleanups

- Move the `nrs` machinery out of `theme-switching.nix` into
  `host-commands.nix` (nixos branch of `switch`). `theme-switching.nix` keeps
  only the `theme-light` / `theme-dark` scripts.
- Remove the `nrs = "nrs"` alias (`shell-core.nix` line 128). `nrs` is replaced
  by `switch`.
- `nrb` (`sudo nixos-rebuild boot`) untouched — nixos-only, outside the trio.
- `git rm home/bin/upgrade` — superseded; avoids PATH-shadowing the new nix-built
  `upgrade`. Dropped legacy steps: `nix profile upgrade '.*'`, `devbox global
  update`, trailing `sync`, and the commented-out cruft (orthogonal to the
  declarative flake flow — YAGNI). Only `nice -n 18` is ported (onto `upgrade`).

## Behavior decisions (settled)

- 3 commands, not 2: sync-mine and upgrade-upstream are independent; you often
  want one without the other.
- `pull` uses `--rebase --autostash` so a dirty working tree (mid-iteration)
  doesn't abort it.
- `upgrade` commits `flake.lock` only **after a successful switch** (proves the
  bump builds — matches "commit after verified"). Push stays **manual**:
  explicit propagation; other hosts then `pull` the committed lock. `flake.lock`
  is shared by all hosts (single flake), so one host upgrades, others pull.
- `upgrade` commits `flake.lock` by pathspec (`git commit flake.lock`), so other
  dirty files in the tree are left untouched.

## Out of scope

- Auto-push on `upgrade`.
- Imperative `nix profile` / `devbox` upgrades.
- Any `pull`/`upgrade` on nixos going through a separate non-tmux rebuild path
  (rejected: would duplicate the rebuild concept; Change X keeps one `switch`).
