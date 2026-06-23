# proot fchmodat2 patch — let korken build read-only directory sources

## Problem

`nix-on-droid switch` on korken fails building `blink-cmp` (and any build that `cp -r`s
a read-only directory tree, e.g. cargo vendor staging):

```
cp: setting permissions for 'source': No such file or directory
```

## Root cause

korken's kernel is 6.6.102. GNU coreutils `cp` sets directory permissions with
**`fchmodat2(dirfd, path, mode, AT_SYMLINK_NOFOLLOW)`** — Linux 6.6 syscall **nr 452**,
the only `chmod` variant supporting `AT_SYMLINK_NOFOLLOW`.

The bumped proot (termux/proot `60485d2`, 2024-05-04) has **no knowledge of
`fchmodat2`**: it is absent from `sysnums.list`, every `sysnums-<arch>.h`, `enter.c`,
and `seccomp.c`. In seccomp mode (korken's default) the unknown syscall is never
trapped, so proot never translates the guest path → the kernel receives an
untranslated path → **ENOENT**.

Evidence:
- `strace`: `fchmodat2(AT_FDCWD, ".../x", 040755, AT_SYMLINK_NOFOLLOW) = -1 ENOENT`.
- Standalone `chmod` (old `fchmodat`, which proot handles) works; `cp` (`fchmodat2`) fails.
- seccomp ruled out: nested proot with `PROOT_NO_SECCOMP=1` still fails (no `enter.c` case either).
- Upstream unfixed: neither termux/proot nor proot-me/proot master defines `fchmodat2`,
  so bumping the rev does not help — a patch is required.

General problem, not blink-cmp-specific: any read-only directory `cp` on korken.

## Fix

New patch `hosts-nix-on-droid/proot-bumped/fchmodat2.patch`, added to the `patches`
list in `proot-termux.nix`. It mirrors the existing `faccessat2` wiring across 4 sites:

1. `src/syscall/sysnums.list`: add `SYSNUM(fchmodat2)` (generates the `PR_fchmodat2` enum).
2. `src/syscall/sysnums-{arm64,x86_64,arm,i386}.h`: add `[ 452 ] = PR_fchmodat2,`
   (fchmodat2 = 452 on all four; x32/sh4 skipped — different numbering, unused by korken).
3. `src/syscall/enter.c`: add `case PR_fchmodat2:` to the **`PR_utimensat` group**
   (reads flags from `SYSARG_4`, honors `AT_SYMLINK_NOFOLLOW`). This is correct for
   fchmodat2's signature `(dirfd, path, mode, flags)` — unlike the plain `PR_fchmodat`
   group which ignores flags and always translates REGULAR.
4. `src/syscall/seccomp.c`: add `{ PR_fchmodat2, 0 },` to `filtered_sysnums` so the
   syscall is actually trapped in seccomp mode.

All-4-arch choice follows the existing `faccessat2` convention (wired in every arch
header) for least surprise.

## Build & delivery

korken cannot build proot itself (cross-build only). Path:

1. Cross-build `prootBumped` locally on gurke (x86_64 → aarch64-android NDK) to confirm
   the patch compiles and obtain the new store-path hash.
2. Push the patch on branch `proot-bump-ci` → `.github/workflows/build-proot.yml` builds
   `ci/proot-bump.nix` and `cachix push fdietze` the new closure.
3. Merge to master. `${prootBumped}` (referenced by `korken.nix`
   `environment.files.prootStatic`) auto-updates to the new hash.

## korken activation sequence (deadlock-aware)

A single `nix-on-droid switch` cannot bootstrap: it builds nvf **before** activation
stages the new proot, but nvf can't build under the *old* proot. So:

1. On korken: substitute the new proot path from cachix and `cp` it to
   `/bin/.proot-static.new` (same step korken.nix's `activationAfter.bumpedProot` does).
2. **Restart the korken app** (manual, on the phone) → `/bin/login` swaps in the new
   fchmodat2-aware proot.
3. `nix-on-droid switch --flake .#korken` → nvf now builds; korken gets the base editor.

## Verification

- Local: patched prootBumped cross-builds on gurke; new hash recorded.
- korken (post-restart): re-run `cp -r <readonly-dir-source> /tmp/x` → succeeds (rc=0).
- korken: `nix-on-droid switch` completes; `nvim` present and runs.

## Out of scope

- Upstream PR to proot-me/proot (worthwhile later; same patch).
- Any nvf config change (the base/lsp split is already done and correct).
