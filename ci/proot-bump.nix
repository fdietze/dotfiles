# Builds nix-on-droid's proot-termux-static with the source rev from upstream
# PR nix-community/nix-on-droid#529 (unstable-2024-05-04 -> unstable-2026-02-20),
# which fixes the TCGETS2 tty ioctl that makes korken's interactive programs go
# tty-blind under the old proot. Built natively on an aarch64 runner (no QEMU,
# and no Android/proot filesystem limits), then shipped to the device.
# Driven by .github/workflows/build-proot.yml; resolves the repo's flake inputs
# via $GITHUB_WORKSPACE so it does not depend on the repo exporting a package.
let
  f = builtins.getFlake (builtins.getEnv "GITHUB_WORKSPACE");
  pkgs = import f.inputs.nixpkgs { system = "aarch64-linux"; };
in
(f.inputs.nix-on-droid.packages.aarch64-linux.prootTermux-aarch64).overrideAttrs (_: {
  version = "unstable-2026-02-20";
  src = pkgs.fetchFromGitHub {
    owner = "termux";
    repo = "proot";
    rev = "ab2e3464d04483b98a0614b470f3f8950d5a6468";
    hash = "sha256-TMYkLmk+NnYcqJKF6RSOkN4S8AI5+HaNcgZZe/5E0vI=";
  };
})
