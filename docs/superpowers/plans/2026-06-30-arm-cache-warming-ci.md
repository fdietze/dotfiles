# Per-architecture CI Cache Warming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On every master push, build each host's full closure in GitHub Actions and push the newly-built deltas to `fdietze.cachix.org`, so slow arm hosts (cubie, korken) download-only on switch.

**Architecture:** Two workflow files split by runner architecture. `build-arm.yml` (ubuntu-24.04-arm) builds cubie + korken closures; `build-x86.yml` (ubuntu-latest) builds gurke's NixOS toplevel + the x86-cross proot. Each job uses `cachix/cachix-action` without `skipPush`, so its post-build-hook auto-pushes only newly-built paths. Building full closures subsumes the old per-package paseo/proot-aarch64 jobs.

**Tech Stack:** GitHub Actions, Nix flakes, DeterminateSystems/nix-installer-action, cachix/cachix-action@v15.

> **Amendments (discovered during execution, 2026-07-01):** Two deviations from
> the task bodies below, reflected in the committed workflows and the spec:
> 1. **korken target** is its **home-manager closure**
>    (`.#nixOnDroidConfigurations.korken.config.home-manager.config.home.activationPackage`),
>    not the full activationPackage — the full generation references nix-on-droid's
>    readOnly app-shipped `prootStatic` storePath (`7qd99…`), absent from all
>    caches, unrealizable in CI.
> 2. **Push is explicit** (`skipPush: true` + `cachix push`), not the auto
>    post-build-hook — the hook did not upload under the DeterminateSystems daemon.
> Also: same-arch hosts build **sequentially in one job**, not one job per host.

## Global Constraints

- Cache name: `fdietze` (host `fdietze.cachix.org`); auth via `${{ secrets.CACHIX_AUTH_TOKEN }}` (already configured, used by current workflows).
- arm runner label: `ubuntu-24.04-arm` (already proven in current `build-paseo.yml`).
- korken build REQUIRES `--impure` (nix-on-droid evaluates `builtins.storePath`, rejected in pure mode). cubie and gurke are pure (no flag).
- Triggers for both files: `push: { branches: [master] }` with NO paths filter, plus `workflow_dispatch`.
- `concurrency: { group: <workflow-name>, cancel-in-progress: true }` per workflow.
- `timeout-minutes: 60` per job.
- Set `skipPush: true` on cachix-action and push each built closure explicitly
  with `cachix push fdietze "$(readlink -f result-*)"` (the auto post-build-hook
  does not upload reliably under the DeterminateSystems Nix daemon).
- Verbatim attr paths (verified by `nix eval` on 2026-06-30):
  - `.#homeConfigurations.cubie.activationPackage`
  - `.#nixOnDroidConfigurations.korken.config.home-manager.config.home.activationPackage` (home closure; the full activationPackage is unrealizable in CI — see Amendments)
  - `.#nixosConfigurations.gurke.config.system.build.toplevel`
  - `ci/proot-bump.nix` (built with `nix build --impure -f ci/proot-bump.nix`)

---

### Task 1: arm workflow (cubie + korken)

**Files:**
- Create: `.github/workflows/build-arm.yml`

**Interfaces:**
- Produces: a workflow that, on master push, realizes and pushes the cubie and korken closures. Later cleanup (Task 3) relies on cubie's closure covering paseo-aarch64.

- [ ] **Step 1: Write the workflow file**

```yaml
# Builds the full aarch64-linux closures of the two slow arm hosts and pushes
# every newly-built path to the fdietze cachix cache, so cubie (1 GB SBC) and
# korken (nix-on-droid) download-only on switch instead of building on-device.
# Building the whole closure subsumes the old per-package paseo-aarch64 build.
#
# Runs natively on ubuntu-24.04-arm (no QEMU). korken's closure references the
# x86-pinned proot store path; the arm runner cannot build x86, so it
# SUBSTITUTES proot from cachix (pushed by build-x86.yml's proot job).
name: build-arm

on:
  push:
    branches: [master]
  workflow_dispatch:

concurrency:
  group: build-arm
  cancel-in-progress: true

jobs:
  cubie:
    runs-on: ubuntu-24.04-arm
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main
      # No skipPush: the post-build-hook auto-pushes every newly-built path.
      - uses: cachix/cachix-action@v15
        with:
          name: fdietze
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
      - name: Build cubie home-manager closure (native aarch64)
        run: nix build -L .#homeConfigurations.cubie.activationPackage -o result-cubie

  korken:
    runs-on: ubuntu-24.04-arm
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: cachix/cachix-action@v15
        with:
          name: fdietze
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
      # --impure: nix-on-droid evaluates builtins.storePath (rejected in pure
      # mode). proot is substituted from cachix, not built here (x86-pinned).
      - name: Build korken nix-on-droid closure (native aarch64)
        run: nix build -L --impure .#nixOnDroidConfigurations.korken.activationPackage -o result-korken
```

- [ ] **Step 2: Validate YAML + attr paths locally**

Run:
```bash
cd ~/projects/dotfiles
nix-shell -p actionlint --run 'actionlint .github/workflows/build-arm.yml'
nix eval --raw .#homeConfigurations.cubie.activationPackage.drvPath >/dev/null && echo CUBIE_OK
nix eval --impure --raw .#nixOnDroidConfigurations.korken.activationPackage.drvPath 2>&1 | grep -q 'proot.*no substituter\|\.drv' && echo KORKEN_EVAL_OK
```
Expected: `actionlint` prints nothing (exit 0); `CUBIE_OK`; `KORKEN_EVAL_OK` (korken eval reaches the proot-substitution stage, proving the attr path resolves — local machine lacks the fdietze substituter so realizing proot fails, which is expected; CI has it).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-arm.yml
git commit -m "ci: build-arm workflow warms cubie+korken closures to cachix"
```

---

### Task 2: x86 workflow (gurke + proot)

**Files:**
- Create: `.github/workflows/build-x86.yml`

**Interfaces:**
- Consumes: `ci/proot-bump.nix` (existing, unchanged).
- Produces: pushes gurke's toplevel (covers paseo-desktop) and the x86-cross proot (korken substitutes it). Cleanup (Task 3) relies on gurke's closure covering paseo-desktop.

- [ ] **Step 1: Write the workflow file**

```yaml
# Builds the x86_64-linux artifacts and pushes new paths to the fdietze cachix
# cache. gurke's full NixOS toplevel (subsumes the paseo desktop app, imported
# by gurke's home.nix) and the bumped proot.
#
# proot-bumped is pinned to system=x86_64-linux (Android NDK cross toolchain
# ships x86 host binaries) and cross-compiles the aarch64-android proot, so it
# must build here on x86, not in build-arm.yml. korken substitutes its output.
name: build-x86

on:
  push:
    branches: [master]
  workflow_dispatch:

concurrency:
  group: build-x86
  cancel-in-progress: true

jobs:
  gurke:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: cachix/cachix-action@v15
        with:
          name: fdietze
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
      - name: Build gurke NixOS toplevel
        run: nix build -L .#nixosConfigurations.gurke.config.system.build.toplevel -o result-gurke

  proot:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: cachix/cachix-action@v15
        with:
          name: fdietze
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
      # --impure: ci/proot-bump.nix resolves flake inputs via builtins.getFlake
      # ($GITHUB_WORKSPACE). Same store path korken's prootStatic references.
      - name: Build bumped proot (x86 NDK cross -> aarch64-android)
        run: nix build -L --impure -f ci/proot-bump.nix -o result-proot
```

- [ ] **Step 2: Validate YAML + attr paths locally**

Run:
```bash
cd ~/projects/dotfiles
nix-shell -p actionlint --run 'actionlint .github/workflows/build-x86.yml'
nix eval --raw .#nixosConfigurations.gurke.config.system.build.toplevel.drvPath >/dev/null && echo GURKE_OK
GITHUB_WORKSPACE="$PWD" nix eval --impure --raw -f ci/proot-bump.nix drvPath 2>&1 | grep -q '\.drv' && echo PROOT_OK
```
Expected: `actionlint` prints nothing; `GURKE_OK`; `PROOT_OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-x86.yml
git commit -m "ci: build-x86 workflow warms gurke toplevel + proot to cachix"
```

---

### Task 3: Remove subsumed workflows and dead CI entry points

**Files:**
- Delete: `.github/workflows/build-paseo.yml` (paseo-aarch64 → cubie closure; paseo-desktop → gurke closure)
- Delete: `.github/workflows/build-proot.yml` (replaced by build-x86.yml's proot job)
- Delete: `ci/paseo.nix` (covered by cubie closure)
- Delete: `ci/paseo-desktop.nix` (covered by gurke closure)
- Keep: `ci/proot-bump.nix` (still used by build-x86.yml)

**Interfaces:**
- Consumes: Tasks 1 and 2 must be committed first (their closures replace these).

- [ ] **Step 1: Verify nothing else references the files being deleted**

Run:
```bash
cd ~/projects/dotfiles
rg -n 'ci/paseo\.nix|ci/paseo-desktop\.nix|build-paseo|build-proot' --glob '!docs/**' || echo NO_REFS
```
Expected: `NO_REFS` (only docs/specs may mention them, which is fine).

- [ ] **Step 2: Delete the files**

```bash
cd ~/projects/dotfiles
git rm .github/workflows/build-paseo.yml .github/workflows/build-proot.yml ci/paseo.nix ci/paseo-desktop.nix
```

- [ ] **Step 3: Confirm ci/proot-bump.nix still present and flake still evaluates**

Run:
```bash
test -f ci/proot-bump.nix && echo PROOT_NIX_KEPT
nix flake check --no-build 2>&1 | tail -1 || true
```
Expected: `PROOT_NIX_KEPT`; flake check has no new errors.

- [ ] **Step 4: Commit**

```bash
git commit -m "ci: drop per-package paseo/proot workflows now subsumed by closures"
```

---

### Task 4: Document the proot-bump ordering gotcha

**Files:**
- Modify: `hosts-nix-on-droid/proot-bumped/default.nix` (append a CI-ordering note to the existing top comment)

**Interfaces:**
- Consumes: Tasks 1-2 (the workflows whose ordering this documents).

- [ ] **Step 1: Add the ordering note**

Locate the existing comment block at the top of `hosts-nix-on-droid/proot-bumped/default.nix` (it explains the x86 NDK cross + single-source-of-truth). Append one paragraph immediately after the existing `# Single source of truth:` paragraph:

```nix
# CI ordering: build-arm.yml (korken) substitutes this x86-built proot from the
# fdietze cachix cache; build-x86.yml builds and pushes it. Both fire in
# parallel on master push, so when you bump the rev below, push that change
# ALONE first (build-x86 caches it), then push closure-affecting changes — or
# re-run build-arm after build-x86 finishes. Unchanged revs are already cached,
# so normal pushes never race.
```

- [ ] **Step 2: Verify the file still evaluates**

Run:
```bash
cd ~/projects/dotfiles
nix eval --impure --raw -f - <<'EOF' 2>&1 | grep -q '\.drv' && echo OK
let f = builtins.getFlake (toString ./.); in
  (import ./hosts-nix-on-droid/proot-bumped { nixpkgs = f.inputs.nixpkgs; }).drvPath
EOF
```
Expected: `OK` (comment-only change does not break evaluation).

- [ ] **Step 3: Commit**

```bash
git add hosts-nix-on-droid/proot-bumped/default.nix
git commit -m "docs: note CI proot/korken ordering in proot-bumped"
```

---

## Self-Review

**Spec coverage:**
- arm workflow (cubie+korken) → Task 1 ✓
- x86 workflow (gurke+proot) → Task 2 ✓
- cachix auto-push, triggers, concurrency, timeout → Global Constraints + Tasks 1-2 ✓
- delete ci/paseo.nix, ci/paseo-desktop.nix, build-paseo.yml, build-proot.yml; keep ci/proot-bump.nix → Task 3 ✓
- proot ordering gotcha documented → Task 4 ✓
- Prerequisite 1 (cubie substituter, on-device/out-of-band) → NOT a repo change; surfaced as a manual post-merge check, see note below.
- Risks 2-3 (korken on plain runner; runner time budget) → validated by the first real CI run, not a code task.

**Manual post-merge check (not a code task):** confirm cubie's Determinate Nix `/etc/nix/nix.conf` lists `fdietze.cachix.org` as a substituter + its public key, else pushed paths are not used on cubie's switch. korken already has it.

**Placeholder scan:** no TBD/TODO; all workflow bodies and commands are concrete.

**Type consistency:** attr paths identical across Global Constraints and Tasks 1-2; output symlink names (`result-cubie`, `result-korken`, `result-gurke`, `result-proot`) are per-job and non-colliding.
