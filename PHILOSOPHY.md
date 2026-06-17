# Dotfiles Philosophy

This repository is the public source of truth for my NixOS, Home Manager, and
portable dotfiles setup.

## Shape

- Use a normal Git repository at `~/projects/dotfiles`.
- Keep `/etc/nixos` only as compatibility glue when useful.
- Treat `$HOME` as runtime state, not as the Git worktree.
- Use NixOS and Home Manager for durable configuration.
- Keep host entrypoints under `hosts-nixos/<hostname>/`.
- Keep reusable NixOS and Home Manager logic under `modules/`.

## Home Files

- Prefer Home Manager modules when they are clear and ergonomic.
- Use Home Manager-managed files for plain dotfiles and XDG config files when a
  module would add noise.
- Keep generated app state, caches, browser state, SSH keys, tokens, and private
  files unmanaged.
- Avoid manual symlink management; let Home Manager own links.

## Scripts

- Keep actively edited scripts in `home/bin`.
- Put `home/bin` on `PATH` directly so script experiments run immediately
  without a rebuild.
- Promote scripts to Nix packages only when declared dependencies,
  reproducibility, or reuse make that worth the ceremony.

## Secrets

- Do not commit secrets.
- Do not write secrets into the Nix store, generated scripts, systemd units,
  desktop files, or long-lived shell environment files.
- Keep secret material in Secret Service, KeePass, SSH agent integrations, or
  service-specific key stores.
- Public config may contain secret lookup commands and public sync paths, but not
  the secret values themselves.

## Tradeoff

The setup should be conventional where convention removes friction: normal Git,
normal flake layout, normal Home Manager ownership. It should stay custom where
that preserves useful feedback loops, especially live-editable personal scripts.
