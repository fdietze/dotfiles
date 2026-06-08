# Nix-on-Droid Korken Host Design

## Goal

Set up an initialized, flake-enabled Nix-on-Droid installation from the existing `scripts/setup-new-host.sh` entrypoint. The Android device is named `korken` in this repository's Nix configuration, even though Nix-on-Droid itself reports the runtime hostname as `localhost` and cannot change it.

## Current State

- `scripts/setup-new-host.sh` supports two modes: full NixOS + Home Manager, and standalone Home Manager.
- The full-system path derives the host name from `hostname`, copies `hosts/template`, runs `nixos-generate-config`, stages `hosts/<hostname>`, and offers `sudo nixos-rebuild switch`.
- `flake.nix` auto-discovers every `hosts/*` directory except `hosts/template` as a NixOS host.
- The flake has no `nix-on-droid` input and no `nixOnDroidConfigurations` output.
- `modules/home-manager/profiles/shell-core.nix` is intended to be portable, but currently sets `home.homeDirectory = "/home/felix"`, which conflicts with Nix-on-Droid's real home directory.

## Approach

Add a third setup mode for Nix-on-Droid instead of trying to reuse the NixOS path. This keeps the existing NixOS and standalone Home Manager behavior unchanged and avoids pretending Android is a NixOS host.

The Nix-on-Droid configuration should live outside `hosts/`, for example under `nix-on-droid/korken.nix`, because `hosts/*` currently means `nixosConfigurations.*`. Reusing `hosts/korken` would require extra filtering or marker files just to avoid creating a broken NixOS configuration.

## Flake Design

Add a `nix-on-droid` flake input and expose `nixOnDroidConfigurations.korken` with `nix-on-droid.lib.nixOnDroidConfiguration`. Use the upstream input with the repository's existing moving `nixpkgs`/Home Manager setup:

```nix
nix-on-droid = {
  url = "github:nix-community/nix-on-droid/master";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

The configuration should:

- import a dedicated Android module such as `./nix-on-droid/korken.nix`;
- use `pkgs = import nixpkgs { system = "aarch64-linux"; overlays = [ nix-on-droid.overlays.default ]; };`, following the upstream flake template;
- pass `home-manager-path = home-manager.outPath`, as required by the upstream Nix-on-Droid Home Manager integration;
- keep existing NixOS `nixosConfigurations` auto-discovery unchanged.

## Android Module Design

The `korken` Nix-on-Droid module should be minimal and shell-focused.

Required settings:

- `user.userName = "felix"`, so generated passwd/user state uses the desired user name.
- `nix.extraOptions` enables `nix-command flakes`, matching the upstream option syntax.
- `system.stateVersion = "24.05"`, matching the latest value documented by the current Nix-on-Droid option reference.
- `home-manager.useGlobalPkgs = true`.
- `home-manager.backupFileExtension = "hm-bak"`.
- `home-manager.config` imports the portable Home Manager profiles:
  - `../modules/home-manager/profiles/shell-core.nix`
  - `../modules/home-manager/profiles/standalone-extras.nix`

The module should not set a hostname. `localhost` is a Nix-on-Droid limitation and the repo-level configuration name `korken` is the stable identifier.

## Home Manager Portability Change

Change `modules/home-manager/profiles/shell-core.nix` so Linux defaults stay the same, but Nix-on-Droid can supply its real values:

```nix
home.username = lib.mkDefault "felix";
home.homeDirectory = lib.mkDefault "/home/felix";
```

This is the smallest safe change because Nix-on-Droid's Home Manager module sets `home.username = config.user.userName` and `home.homeDirectory = config.user.home`, where `config.user.home` is `/data/data/com.termux.nix/files/home`. Using `mkDefault` avoids an option conflict while preserving standalone Linux behavior.

## Setup Script Design

Extend `scripts/setup-new-host.sh` with a third mode:

```text
[3] Nix-on-Droid (korken)
```

Mode `3` should:

- require `nix-on-droid` in `PATH` and fail with a clear message if missing;
- use the fixed flake output name `korken` instead of `hostname`;
- run `nix-on-droid switch --flake "$REPO_DIR#korken"`;
- avoid `nixos-generate-config`;
- avoid creating `hosts/localhost`;
- avoid `sudo` and `nixos-rebuild`.

The existing git-bootstrap behavior should remain shared by all modes: ensure `git`, clone the repository if missing, then evaluate the current architecture for informational output.

## Error Handling

- If mode `3` is selected outside Nix-on-Droid, print that `nix-on-droid` was not found and exit non-zero.
- Do not attempt to install or bootstrap the Android app; the script assumes it is already running inside an initialized Nix-on-Droid app with flakes available.
- Do not special-case runtime hostname `localhost`; it is expected and irrelevant for this mode.

## Verification

- Run `bash -n scripts/setup-new-host.sh`.
- Evaluate the flake output shape with `nix flake show` or a targeted `nix eval` for `nixOnDroidConfigurations.korken` if local evaluation supports the Nix-on-Droid input.
- Build/evaluate incrementally before activation. Do not run `nix-on-droid switch` from this workstation and do not run any system-activating rebuild.
