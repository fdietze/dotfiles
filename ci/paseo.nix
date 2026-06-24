# CI entry point: resolves the repo's flake inputs via $GITHUB_WORKSPACE and
# builds the aarch64-linux paseo package — the exact store path that
# hosts-home/cubie.nix references (flake-inputs.paseo.packages.aarch64-linux.paseo).
# Pushed to the fdietze cachix cache so the 1 GB cubie SBC substitutes it on
# `home-manager switch` instead of building it locally (the TypeScript server
# build OOMs there: node aborts with code 134 mid-`tsc`).
let
  f = builtins.getFlake (builtins.getEnv "GITHUB_WORKSPACE");
in
  f.inputs.paseo.packages.aarch64-linux.paseo
