# Opencode Sandbox Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap the `opencode` command in the `nono` sandbox using the `claude` profile and provide a `vanilla-opencode` escape hatch.

**Architecture:** We will replace the default `opencode` package in `packages-cli.nix` with custom-wrapped script binaries built via Nix. These binaries wrap the underlying `opencode` command with `nice`, `ionice`, and `nono`.

**Tech Stack:** Nix, Home Manager, Bash, Nono sandbox.

---

### Task 1: Modify packages-cli.nix to wrap opencode

**Files:**
- Modify: `modules/home-manager/profiles/packages-cli.nix`

- [ ] **Step 1: Edit `modules/home-manager/profiles/packages-cli.nix` to replace raw `opencode` with custom wrappers**

Remove `opencode` from the list of packages inside `with pkgs; [` and add custom wrapped packages at the end.

Let's locate where `opencode` is defined. It is at line 73:
```nix
      opencode
```
We will delete it from line 73. Then, at the bottom (around line 127, right below `vanilla-claude`), we will add:
```nix
      # Wrap `opencode` in the nono sandbox using the same profile as claude.
      # `nice -n 19` + `ionice -c 3` keep it from starving interactive work.
      (pkgs.writeShellScriptBin "opencode" ''
        exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 \
          ${pkgs.nono}/bin/nono run --profile claude -- \
          ${pkgs.opencode}/bin/opencode --dangerously-skip-permissions "$@"
      '')

      # Escape hatch: stock opencode on the host, without the sandbox.
      (pkgs.writeShellScriptBin "vanilla-opencode" ''
        exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 \
          ${pkgs.opencode}/bin/opencode "$@"
      '')
```

- [ ] **Step 2: Verify Nix configuration syntax**

Run: `nix-instantiate --parse modules/home-manager/profiles/packages-cli.nix`
Expected output: No syntax errors.

- [ ] **Step 3: Build the Nix configuration to verify it compiles**

Since we don't activate, we can run a dry build or build the configuration to verify it compiles.
Run: `nixos-rebuild build --flake .`
Expected output: A successful build (a symlink `./result` will be created pointing to the built system derivation).

- [ ] **Step 4: Commit the changes**

Run:
```bash
git add modules/home-manager/profiles/packages-cli.nix
git commit -m "feat(hm): wrap opencode in the nono sandbox with vanilla-opencode escape hatch"
```
