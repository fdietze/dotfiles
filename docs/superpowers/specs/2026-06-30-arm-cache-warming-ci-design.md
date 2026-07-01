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

Both hosts build **sequentially in one job** (`arm`) so korken reuses cubie's
just-built shared aarch64 store paths instead of a second parallel runner
rebuilding them.

- cubie: `nix build .#homeConfigurations.cubie.activationPackage`
- korken: `nix build --impure .#nixOnDroidConfigurations.korken.config.home-manager.config.home.activationPackage`
  - We build korken's **home-manager closure**, NOT the full nix-on-droid
    activationPackage. The full generation references nix-on-droid's default
    `environment.files.prootStatic` — a `readOnly` `builtins.storePath`
    (`7qd99…proot-termux-static-…-2024-05-04`) shipped inside the Android app and
    present in NO public cache (cache.nixos.org / numtide / fdietze all 404), so
    a CI runner cannot realize it. `readOnly = true` also blocks overriding it to
    prootBumped. On-device that path is app-present, and prootBumped substitutes
    from cachix, so the trivial system-generation wrapper builds fine on switch.
    korken's heavy aarch64 packages (nvf/neovim, pi/claude agents) live in the
    home closure — exactly what we pre-warm.
  - `--impure` is required: nix-on-droid evaluates `builtins.storePath` (rejected
    in pure mode).

### `.github/workflows/build-x86.yml` — `runs-on: ubuntu-latest`

Both build **sequentially in one job** (`x86`).

- proot: `nix build --impure -f ci/proot-bump.nix` (builds+pushes the bumped
  proot `scf3d1a1…`; korken's on-device switch substitutes it)
- gurke: `nix build .#nixosConfigurations.gurke.config.system.build.toplevel`
  - proot-bumped is pinned to `system = "x86_64-linux"` because the Android NDK
    cross toolchain ships x86 host binaries; it cross-compiles the aarch64-android
    proot. This is why it stays a separate x86 job and cannot fold into the arm
    closure build. korken substitutes its output (see above).

### Common to both files

- Triggers: `push: { branches: [master] }` with **no paths filter** (any module
  edit or `flake.lock` bump can change a closure), plus `workflow_dispatch`.
- `concurrency: { group: <workflow>, cancel-in-progress: true }` per workflow.
- Each job: `actions/checkout@v4`, `DeterminateSystems/nix-installer-action@main`,
  `cachix/cachix-action@v15` with `name: fdietze`,
  `authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}`, and **`skipPush: true`** plus an
  explicit `cachix push fdietze "$(readlink -f result-*)"` step per built
  closure. The automatic post-build-hook (no `skipPush`) was tried first but did
  NOT reliably upload under the DeterminateSystems Nix daemon (proot built `✓`
  yet stayed 404 in cachix), so we push explicitly like the original workflows;
  `cachix push` skips paths already present, so only new deltas upload.
- `timeout-minutes: 60` per job (matches existing workflows).

### Cleanup (DRY)

Delete, since the closures now cover them:

- `ci/paseo.nix` (covered by cubie closure)
- `ci/paseo-desktop.nix` (covered by gurke closure)
- `.github/workflows/build-paseo.yml`
- `.github/workflows/build-proot.yml`

Keep `ci/proot-bump.nix` (still the x86 proot entry point).

## No CI-time proot race

An earlier design built korken's *full* activationPackage, which references the
bumped proot, creating an ordering race with the x86 proot build. Building only
korken's home closure removed it: the home closure references neither the bumped
proot nor the app proot. build-x86 still builds+pushes the bumped proot purely
for korken's ON-DEVICE switch (where the system generation installs it). Since
normal pushes don't change the proot rev, it stays cached; on a rev bump, push
the proot change first so the device can substitute it.

## Prerequisites / risks to validate

1. **cubie substituter**: cubie must list `fdietze.cachix.org` as a substituter
   (+ its public key) in its Determinate Nix `/etc/nix/nix.conf`, configured
   out-of-band. korken already has it (`hosts-nix-on-droid/korken.nix`). Verify
   on-device or the pushed paths won't be used.
2. **korken system-layer builds on-device**: the home closure is pre-warmed, but
   the small nix-on-droid system generation (openssh + activation scripts +
   generation wrapper) still builds on-device on switch. It is trivial (no heavy
   compiles) and references only app-present (7qd99) / cached (bumped proot)
   paths, so it does not OOM — confirm on the first real switch.
3. **Runner time budget**: cold cubie/gurke closures must finish within the
   60-minute job timeout; most paths come from upstream caches
   (cache.nixos.org, cache.numtide.com, noctalia.cachix.org).
