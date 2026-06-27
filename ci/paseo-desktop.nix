# CI entry point: builds the x86_64-linux paseo desktop package and pushes to
# fdietze cachix cache so gurke can substitute it on `switch`.
let
  f = builtins.getFlake (builtins.getEnv "GITHUB_WORKSPACE");
in
  f.inputs.paseo.packages.x86_64-linux.desktop
