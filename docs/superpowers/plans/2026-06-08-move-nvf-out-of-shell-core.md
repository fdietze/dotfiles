# Move NVF out of shell-core and enable it on Gurke

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the NVF (Neovim Flake) Neovim configuration optional on a per-host basis, stripping it from the common headless core profile and explicitly activating it for the `gurke` host.

**Architecture:** Remove `../nvf.nix` from the imports list in `modules/home-manager/profiles/shell-core.nix`, and add `../../modules/home-manager/nvf.nix` to the imports of `hosts/gurke/home.nix` with a descriptive comment explaining why it is loaded there.

**Tech Stack:** Nix, Home Manager, NixOS

---

### Task 1: De-couple NVF from the Shell-Core Profile

**Files:**
- Modify: `modules/home-manager/profiles/shell-core.nix:23`

- [ ] **Step 1: Edit shell-core.nix to remove the nvf import**

Remove the line `../nvf.nix` from the `imports` attribute in `modules/home-manager/profiles/shell-core.nix`.

```nix
  imports = [
    ../shell.nix
    ../dotfiles.nix
    ../git.nix
    ../yazi.nix
    ./packages-cli.nix
  ];
```

- [ ] **Step 2: Commit the change to shell-core.nix**

```bash
git add modules/home-manager/profiles/shell-core.nix
git commit -m "refactor(hm): remove nvf from default shell-core profile"
```

---

### Task 2: Explicitly Activate NVF on gurke

**Files:**
- Modify: `hosts/gurke/home.nix`

- [ ] **Step 1: Edit hosts/gurke/home.nix to import nvf.nix**

Add `../../modules/home-manager/nvf.nix` to the `imports` block and add a comment documenting its presence on the host.

```nix
{...}: {
  imports = [
    ../../modules/home-manager/shared.nix
    ../../modules/home-manager/firefox.nix
    ../../modules/home-manager/desktops/gnome.nix
    ../../modules/home-manager/desktops/herbstluftwm.nix
    ../../modules/home-manager/desktops/noctalia-niri.nix
    # NVF Neovim configuration explicitly enabled for this host.
    ../../modules/home-manager/nvf.nix
  ];
}
```

- [ ] **Step 2: Verify the configuration builds successfully**

Run a non-activating rebuild check for `gurke` to ensure syntax and module paths are correct.

Run:
```bash
nix build .#nixosConfigurations.gurke.config.system.build.toplevel --no-link
```

Expected output: Command exits successfully with code `0`.

- [ ] **Step 3: Commit the change to gurke/home.nix**

```bash
git add hosts/gurke/home.nix
git commit -m "feat(gurke): explicitly activate NVF Neovim configuration"
```
