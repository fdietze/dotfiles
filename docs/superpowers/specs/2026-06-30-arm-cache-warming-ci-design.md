# Per-architecture CI cache warming

Date: 2026-06-30

## Problem

Two slow aarch64 hosts switch against this flake:

- `cubie` — 1 GB SBC, standalone Home Manager (`homeConfigurations.cubie`).
- `korken` — Android nix-on-droid (`nixOnDroidConfigurations.korken`).

On `switch` they must realize their full closure. When a path is not in any
binary cache they build it on-device, which is slow and sometimes OOMs (e.g.
paseo's TypeScript build aborts with node code 134 on cubie's 1 GB).

Today CI hand-picks individual packages to pre-build: `build-paseo.yml` (paseo
aarch64 + paseo desktop x86) and `build-proot.yml` (proot cross-built on x86).
Anything else not upstream-cached still builds on-device.

## Goal

On every master push, CI builds whatever is not yet cached for each host's
**full closure** and pushes the newly-built deltas to `fdietze.cachix.org`. The
slow arm hosts then download-only on switch — no on-device builds.

## Design

Workflows are split **by runner architecture**, not by package. Building a host's
full closure subsumes the per-package builds that live inside it:

- cubie's closure contains paseo aarch64 → the standalone paseo-aarch64 build dissolves.
- gurke's closure contains the paseo desktop app (gurke `home.nix` imports
  `paseo-desktop.nix`) → the standalone paseo-desktop build dissolves.

### `.github/workflows/build-arm.yml` — `runs-on: ubuntu-24.04-arm`

- job `cubie`: `nix build .#homeConfigurations.cubie.activationPackage`
- job `korken`: `nix build --impure .#nixOnDroidConfigurations.korken.activationPackage`
  - `--impure` is required: nix-on-droid evaluates `builtins.storePath` (rejected
    in pure mode). Confirmed by `nix eval` on 2026-06-30.
  - korken's closure only *references* the x86-pinned proot store path; the arm
    runner cannot build an x86 derivation, so it **substitutes** proot from
    `fdietze.cachix.org`.

### `.github/workflows/build-x86.yml` — `runs-on: ubuntu-latest`

- job `gurke`: `nix build .#nixosConfigurations.gurke.config.system.build.toplevel`
- job `proot`: `nix build --impure -f ci/proot-bump.nix`
  - proot-bumped is pinned to `system = "x86_64-linux"` because the Android NDK
    cross toolchain ships x86 host binaries; it cross-compiles the aarch64-android
    proot. This is why it stays a separate x86 job and cannot fold into the arm
    closure build. korken substitutes its output (see above).

### Common to both files

- Triggers: `push: { branches: [master] }` with **no paths filter** (any module
  edit or `flake.lock` bump can change a closure), plus `workflow_dispatch`.
- `concurrency: { group: <workflow>, cancel-in-progress: true }` per workflow.
- Each job: `actions/checkout@v4`, `DeterminateSystems/nix-installer-action@main`,
  `cachix/cachix-action@v15` with `name: fdietze` and
  `authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}`, **without `skipPush`**. The
  action installs a post-build-hook that pushes each path as it is built;
  substituted/downloaded paths are not re-pushed, so only the genuinely-new
  deltas go up — exactly "build what's not cached, push it".
- `timeout-minutes: 60` per job (matches existing workflows).

### Cleanup (DRY)

Delete, since the closures now cover them:

- `ci/paseo.nix` (covered by cubie closure)
- `ci/paseo-desktop.nix` (covered by gurke closure)
- `.github/workflows/build-paseo.yml`
- `.github/workflows/build-proot.yml`

Keep `ci/proot-bump.nix` (still the x86 proot entry point).

## Gotcha: proot must be cached before korken

korken substitutes the x86-pinned proot; the arm and x86 workflows fire in
parallel on the same push. If the proot rev is bumped in a push, the korken arm
job may try to substitute proot before the x86 job has pushed it → korken fails.

Mitigation (accepted, KISS): the proot rev (`hosts-nix-on-droid/proot-bumped/
default.nix`) changes rarely. Normal pushes don't touch it, so it is already
cached and there is no race. On a rev bump, push the proot change alone first
(x86 caches it), then push closure-affecting changes — or simply re-run the arm
workflow after x86 finishes.

## Prerequisites / risks to validate

1. **cubie substituter**: cubie must list `fdietze.cachix.org` as a substituter
   (+ its public key) in its Determinate Nix `/etc/nix/nix.conf`, configured
   out-of-band. korken already has it (`hosts-nix-on-droid/korken.nix`). Verify
   on-device or the pushed paths won't be used.
2. **korken on a plain runner**: first arm run validates that the nix-on-droid
   `activationPackage` builds fully on a stock aarch64 runner, with no
   on-device-only dependency besides the substituted proot.
3. **Runner time budget**: cold cubie/gurke closures must finish within the
   60-minute job timeout; most paths come from upstream caches
   (cache.nixos.org, cache.numtide.com, noctalia.cachix.org).
