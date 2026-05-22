{
  lib,
  rustPlatform,
  git,
}:

rustPlatform.buildRustPackage {
  pname = "xcwd-home";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # Integration tests spawn `git init` to verify the git-root promotion policy.
  nativeCheckInputs = [ git ];

  meta.mainProgram = "xcwd-home";
}
