# Nix-on-Droid SSH Helper Design

## Goal

Provide reliable manual SSH access to the `korken` Nix-on-Droid device without relying on ad-hoc profile packages or an Android service manager.

## Design

The `korken` module will install OpenSSH declaratively through `environment.packages` and expose one command, `sshd-start`. The command starts `sshd` in the foreground on port `8022` using a config generated during activation.

Activation creates `$HOME/.ssh`, installs a repo-managed `authorized_keys`, and generates a persistent ed25519 host key under `$HOME/.ssh/nix-on-droid-sshd` if one is not already present. This keeps user identity and host identity stable across `nix-on-droid switch` runs.

Tailscale remains outside this config as a separate Android app. The SSH daemon listens on `0.0.0.0:8022`; LAN or Tailscale reachability is handled by Android networking.

## Security

Password and keyboard-interactive authentication are disabled. Only committed public keys in `nix-on-droid/ssh/authorized_keys` are accepted. The server is not auto-started, so exposure is limited to sessions where `sshd-start` is run manually.

## Verification

Local verification should evaluate the generated `sshd-start` package and activation snippet, parse the Nix module, and confirm `pkgs.openssh` is included in `environment.packages`. Device verification should pull the commit, run `nix-on-droid switch --flake ~/projects/dotfiles#korken`, run `sshd-start`, and connect with the committed private-key counterpart.
