{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "polybar-status";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  # Keep Cargo dependency resolution in this local crate so Polybar status can
  # use protocol crates without forcing a full NixOS build during development.
  cargoLock.lockFile = ./Cargo.lock;

  meta.mainProgram = "polybar-status";
}
