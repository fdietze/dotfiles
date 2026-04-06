- automatically read analyze relevant log files and/or run commands like journalctl to get them
- automatically read relevant man pages
- you can assume all binaries in the nix store exist when referencing like this: "${pkgs.mypackage}/bin/mycommand"
- automatically apply changes using `sudo nixos-rebuild switch`
- you can read specific files and dirs, like ~/bin or ~/.config IN $HOME, but not list files in home
- use nixos-option to find nixos options, e.g. services.xserver.xkb.layout

@flake.nix
@configuration.nix
@hardware-configuration.nix
@home.nix
@home
