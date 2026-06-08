# Nix-on-Droid Korken Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Nix-on-Droid `korken` configuration and make `scripts/setup-new-host.sh` activate it from an initialized Nix-on-Droid app.

**Architecture:** Keep Android separate from NixOS hosts by adding `nixOnDroidConfigurations.korken` and a dedicated `nix-on-droid/korken.nix` module outside `hosts/`. Reuse the portable Home Manager shell profile by making its Linux user/home settings defaults so Nix-on-Droid can supply the real Android home directory.

**Tech Stack:** Nix flakes, Nix-on-Droid module system, Home Manager, Bash.

---

## File Structure

- Modify `modules/home-manager/profiles/shell-core.nix`: make `home.username` and `home.homeDirectory` defaults instead of forced values, preserving Linux behavior while allowing Nix-on-Droid's Home Manager module to override them.
- Create `nix-on-droid/korken.nix`: define the Android system module for the `korken` flake output with user `felix`, flakes enabled, Home Manager shell profile, and `system.stateVersion = "24.05"`.
- Modify `flake.nix`: add the `nix-on-droid` input, pass it through `outputs`, define `mkNixOnDroid`, and expose `nixOnDroidConfigurations.korken` without changing `nixosConfigurations` host auto-discovery.
- Modify `scripts/setup-new-host.sh`: add mode `[3] Nix-on-Droid (korken)` that runs `nix-on-droid switch --flake "$REPO_DIR#korken"` and avoids NixOS-specific host generation.

## Task 1: Make Shell Core Home Defaults Overridable

**Files:**

- Modify: `modules/home-manager/profiles/shell-core.nix:10-28`

- [ ] **Step 1: Inspect the current forced Home Manager identity settings**

Run:

```bash
grep -n 'home\.username\|home\.homeDirectory' modules/home-manager/profiles/shell-core.nix
```

Expected output before the change:

```text
26:  home.username = "felix";
27:  home.homeDirectory = "/home/felix";
```

- [ ] **Step 2: Change the profile arguments and defaults**

Edit `modules/home-manager/profiles/shell-core.nix` so the function header includes `lib` and the identity settings use `lib.mkDefault`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";
in {
```

Replace the existing identity assignments with:

```nix
  home.username = lib.mkDefault "felix";
  home.homeDirectory = lib.mkDefault "/home/felix";
```

- [ ] **Step 3: Verify standalone Linux Home Manager still evaluates to the same user and home**

Run:

```bash
nix eval .#homeConfigurations."felix@x86_64-linux".config.home.username --raw
```

Expected output:

```text
felix
```

Run:

```bash
nix eval .#homeConfigurations."felix@x86_64-linux".config.home.homeDirectory --raw
```

Expected output:

```text
/home/felix
```

- [ ] **Step 4: Commit the portability change**

Run:

```bash
git add modules/home-manager/profiles/shell-core.nix
git commit -m "refactor(hm): allow shell core home overrides"
```

## Task 2: Add the Korken Nix-on-Droid Module

**Files:**

- Create: `nix-on-droid/korken.nix`

- [ ] **Step 1: Create the Nix-on-Droid configuration directory and module**

Create `nix-on-droid/korken.nix` with this content:

```nix
{
  pkgs,
  ...
}: {
  # Nix-on-Droid keeps Android's runtime hostname as "localhost"; the stable
  # repository identifier for this device is the flake output name "korken".
  user = {
    userName = "felix";
    shell = "${pkgs.zsh}/bin/zsh";
  };

  # Nix-on-Droid's option reference uses nix.extraOptions for nix.conf text.
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  home-manager = {
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
    config = {...}: {
      imports = [
        ../modules/home-manager/profiles/shell-core.nix
        ../modules/home-manager/profiles/standalone-extras.nix
      ];
    };
  };

  # Latest stateVersion listed in the current Nix-on-Droid option reference.
  system.stateVersion = "24.05";
}
```

- [ ] **Step 2: Run a syntax parse through Nix**

Run:

```bash
nix-instantiate --parse nix-on-droid/korken.nix >/dev/null
```

Expected output: no output and exit code `0`.

- [ ] **Step 3: Commit the Android module**

Run:

```bash
git add nix-on-droid/korken.nix
git commit -m "feat(korken): add nix-on-droid module"
```

## Task 3: Expose nixOnDroidConfigurations.korken

**Files:**

- Modify: `flake.nix:26-44`
- Modify: `flake.nix:46-57`
- Modify: `flake.nix:122-154`

- [ ] **Step 1: Add the `nix-on-droid` input**

In `flake.nix`, add this input after the existing `home-manager` input and before `nix-index-database`:

```nix
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
```

The surrounding input block should become:

```nix
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nix-index-database.url = "github:nix-community/nix-index-database";
```

- [ ] **Step 2: Add `nix-on-droid` to the outputs argument set**

In `flake.nix`, add `nix-on-droid,` after `home-manager,`:

```nix
    home-manager,
    nix-on-droid,
    nix-index-database,
```

- [ ] **Step 3: Add a small Nix-on-Droid configuration helper**

In the `let` block, add this helper after `mkHome`:

```nix
    mkNixOnDroid = deviceName:
      nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [./nix-on-droid/${deviceName}.nix];

        # The upstream flake template recommends the Nix-on-Droid overlay; this
        # pkgs instance also permits the same unfree CLI tools as standalone HM.
        pkgs = import nixpkgs {
          system = "aarch64-linux";
          overlays = [nix-on-droid.overlays.default];
          config.allowUnfree = true;
        };

        home-manager-path = home-manager.outPath;
      };
```

The helper should appear before the `in {` that starts the outputs attrset.

- [ ] **Step 4: Add the `korken` output**

In the outputs attrset, keep the existing `nixosConfigurations` and `homeConfigurations`, then add:

```nix
    # "nix-on-droid switch --flake .#korken"
    nixOnDroidConfigurations = {
      korken = mkNixOnDroid "korken";
    };
```

The final outputs attrset should contain all three top-level outputs:

```nix
    nixosConfigurations = lib.genAttrs hostNames mkHost;

    homeConfigurations = {
      "felix@x86_64-linux" = mkHome "x86_64-linux";
      "felix@aarch64-linux" = mkHome "aarch64-linux";
    };

    nixOnDroidConfigurations = {
      korken = mkNixOnDroid "korken";
    };
```

- [ ] **Step 5: Update the lock file for the new input**

Run:

```bash
nix flake lock --update-input nix-on-droid
```

Expected result: `flake.lock` gains the `nix-on-droid` input and any required transitive inputs. If Nix reports that `--update-input` is deprecated, rerun the command it suggests for updating only `nix-on-droid`.

- [ ] **Step 6: Verify the flake exposes the Android configuration**

Run:

```bash
nix flake show --all-systems
```

Expected output includes a `nixOnDroidConfigurations` section with `korken`.

Run:

```bash
nix eval .#nixOnDroidConfigurations.korken.config.user.userName --raw
```

Expected output:

```text
felix
```

Run:

```bash
nix eval .#nixOnDroidConfigurations.korken.config.home-manager.config.home.homeDirectory --raw
```

Expected output:

```text
/data/data/com.termux.nix/files/home
```

- [ ] **Step 7: Verify existing Linux outputs still evaluate**

Run:

```bash
nix eval .#homeConfigurations."felix@x86_64-linux".config.home.homeDirectory --raw
```

Expected output:

```text
/home/felix
```

Run:

```bash
nix eval .#nixosConfigurations.gurke.config.networking.hostName --raw
```

Expected output:

```text
gurke
```

- [ ] **Step 8: Commit the flake output**

Run:

```bash
git add flake.nix flake.lock
git commit -m "feat(korken): expose nix-on-droid flake output"
```

## Task 4: Add Nix-on-Droid Mode to setup-new-host.sh

**Files:**

- Modify: `scripts/setup-new-host.sh:37-84`

- [ ] **Step 1: Update the mode prompt**

Replace the current prompt block:

```bash
printf '\nWas einrichten?\n  [1] NixOS + Home Manager (ganzes System)\n  [2] Nur Home Manager (Shell-Profil)\n'
read -r -p "Auswahl [1/2]: " MODE </dev/tty
```

with:

```bash
printf '\nWas einrichten?\n  [1] NixOS + Home Manager (ganzes System)\n  [2] Nur Home Manager (Shell-Profil)\n  [3] Nix-on-Droid (korken)\n'
read -r -p "Auswahl [1/2/3]: " MODE </dev/tty
```

- [ ] **Step 2: Add the Nix-on-Droid branch after the Home Manager branch**

Insert this branch after the existing `if [ "$MODE" = "2" ]; then ... fi` block and before `# 5. NixOS + Home Manager.`:

```bash
if [ "$MODE" = "3" ]; then
  # 5. Nix-on-Droid: Der Laufzeit-Hostname bleibt dort immer "localhost";
  #    die stabile Geräte-ID ist deshalb der Flake-Output "korken".
  if ! command -v nix-on-droid >/dev/null 2>&1; then
    say "nix-on-droid nicht gefunden — Modus 3 muss in der initialisierten Nix-on-Droid-App laufen."
    exit 1
  fi

  say "Nix-on-Droid-Konfiguration aktivieren: korken"
  nix-on-droid switch --flake "$REPO_DIR#korken"
  say "Fertig. Neue Shell starten (z. B. 'exec zsh')."
  exit 0
fi
```

- [ ] **Step 3: Renumber the NixOS section comment**

Change:

```bash
# 5. NixOS + Home Manager.
```

to:

```bash
# 6. NixOS + Home Manager.
```

- [ ] **Step 4: Check Bash syntax**

Run:

```bash
bash -n scripts/setup-new-host.sh
```

Expected output: no output and exit code `0`.

- [ ] **Step 5: Verify the new mode text is present without running activation**

Run:

```bash
grep -n 'Nix-on-Droid\|korken\|nix-on-droid switch' scripts/setup-new-host.sh
```

Expected output contains lines for the prompt, the `localhost` comment, the `command -v nix-on-droid` check, and `nix-on-droid switch --flake "$REPO_DIR#korken"`.

- [ ] **Step 6: Commit the setup script mode**

Run:

```bash
git add scripts/setup-new-host.sh
git commit -m "feat(setup): add nix-on-droid korken mode"
```

## Task 5: Final Verification

**Files:**

- Verify: `modules/home-manager/profiles/shell-core.nix`
- Verify: `nix-on-droid/korken.nix`
- Verify: `flake.nix`
- Verify: `scripts/setup-new-host.sh`

- [ ] **Step 1: Check the working tree for unrelated changes**

Run:

```bash
git status --short
```

Expected result: the committed task files are clean. Existing unrelated user changes, if present, remain unstaged and untouched.

- [ ] **Step 2: Re-run syntax and flake checks**

Run:

```bash
bash -n scripts/setup-new-host.sh
```

Expected output: no output and exit code `0`.

Run:

```bash
nix-instantiate --parse nix-on-droid/korken.nix >/dev/null
```

Expected output: no output and exit code `0`.

Run:

```bash
nix eval .#nixOnDroidConfigurations.korken.config.user.userName --raw
```

Expected output:

```text
felix
```

Run:

```bash
nix eval .#nixOnDroidConfigurations.korken.config.home-manager.config.home.homeDirectory --raw
```

Expected output:

```text
/data/data/com.termux.nix/files/home
```

Run:

```bash
nix eval .#homeConfigurations."felix@x86_64-linux".config.home.homeDirectory --raw
```

Expected output:

```text
/home/felix
```

- [ ] **Step 3: Do not activate from this workstation**

Do not run:

```bash
nix-on-droid switch --flake "$REPO_DIR#korken"
```

The activation command is intended to run inside the initialized Nix-on-Droid app through `scripts/setup-new-host.sh` mode `3`.
