# Bumped proot-termux-static (upstream PR nix-community/nix-on-droid#529:
# termux/proot rev ab2e3464, unstable-2026-02-20), which fixes the TCGETS2 tty
# ioctl that makes korken's newer-glibc interactive programs go tty-blind under
# the old app-bundled proot (nix-on-droid#515).
#
# Built with the prebuilt Android NDK cross toolchain (./proot-termux.nix +
# ./talloc-static.nix) instead of nix-on-droid's source-LLVM build: minutes and
# low-resource (the source-LLVM build is too heavy for free CI runners). talloc
# is bumped to 2.4.4 and links its replace objects, both required for bionic.
#
# Single source of truth: ci/proot-bump.nix and korken's
# environment.files.prootStatic both import this, so they evaluate to the SAME
# store path and korken substitutes the CI-built proot from the fdietze cachix
# cache (it can't build it: nix-on-droid's cross machinery fails under the
# on-device proot filesystem).
#
# CI ordering: build-arm.yml (korken) substitutes this x86-built proot from the
# fdietze cachix cache; build-x86.yml builds and pushes it. Both fire in
# parallel on master push, so when you bump the rev below, push that change
# ALONE first (build-x86 caches it), then push closure-affecting changes — or
# re-run build-arm after build-x86 finishes. Unchanged revs are already cached,
# so normal pushes never race.
#
# system is pinned to x86_64-linux because the Android NDK ships x86_64 host
# binaries: the build must run on x86 (CI: ubuntu-latest) and cross-compile the
# aarch64-android proot. korken (aarch64) therefore can't build this derivation
# and always substitutes the path from cachix; the output is a native aarch64
# binary that runs on the device.
{nixpkgs}: let
  pkgs = import nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true; # Android NDK is unfree
  };
  cross = pkgs.pkgsCross.aarch64-android-prebuilt;
  staticStdenv = cross.stdenvAdapters.makeStaticBinaries cross.stdenv;
  tallocStatic = import ./talloc-static.nix {
    pkgsCross = cross;
    inherit (pkgs) fetchurl pkg-config wafHook python3;
  };
in
  (cross.callPackage ./proot-termux.nix {
    talloc = tallocStatic;
    stdenv = staticStdenv;
  })
  .overrideAttrs (o: {
    version = "unstable-2026-02-20";
    src = pkgs.fetchFromGitHub {
      owner = "termux";
      repo = "proot";
      rev = "ab2e3464d04483b98a0614b470f3f8950d5a6468";
      hash = "sha256-TMYkLmk+NnYcqJKF6RSOkN4S8AI5+HaNcgZZe/5E0vI=";
    };
    # The Android NDK clang defaults to -fPIE -pie. proot embeds a loader at a
    # fixed text address (-Ttext=0x2000000000) and segfaults at startup as a PIE,
    # so force a plain non-PIE static binary (nix-on-droid's source-LLVM
    # toolchain produces non-PIE by default; the NDK does not).
    CFLAGS = (o.CFLAGS or []) ++ ["-fno-pie"];
    LDFLAGS = (o.LDFLAGS or []) ++ ["-no-pie"];
  })
