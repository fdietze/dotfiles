let
  flake = builtins.getFlake (toString ../../../../..);
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
in
  pkgs.mkShell {
    packages = [
      pkgs.cargo
      pkgs.rustc
      pkgs.rustfmt
      pkgs.clippy
    ];
  }
