# CI entry point: resolves the repo's flake inputs via $GITHUB_WORKSPACE and
# builds the shared bumped proot derivation, so the path pushed to cachix is the
# exact store path korken's environment.files.prootStatic references.
# See nix-on-droid/proot-bumped/ for the actual derivation.
let
  f = builtins.getFlake (builtins.getEnv "GITHUB_WORKSPACE");
in
  import ../nix-on-droid/proot-bumped {nixpkgs = f.inputs.nixpkgs;}
