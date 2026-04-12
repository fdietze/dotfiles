- the nixos and home manager configurations should be the source of truth
- automatically read analyze relevant log files and/or run commands like journalctl to get them
- automatically read relevant man pages
- you can assume all binaries in the nix store exist when referencing like this: "${pkgs.mypackage}/bin/mycommand"
- you can read specific files and dirs, like ~/bin or ~/.config IN $HOME, but not list files in home
- use nixos-option to find nixos options, e.g. services.xserver.xkb.layout
- automatically apply changes using `sudo nixos-rebuild switch`

configuration entrypoints:
- flake.nix # nixos flake
- configuration.nix # nixos
- home.nix # home-manager
