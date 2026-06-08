# Nix-on-Droid SSH Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a declarative manual SSH server helper for the `korken` Nix-on-Droid device.

**Architecture:** `nix-on-droid/korken.nix` owns OpenSSH installation, activation-time key/config creation, and a generated `sshd-start` wrapper. Public keys are stored in `nix-on-droid/ssh/authorized_keys`.

**Tech Stack:** Nix-on-Droid modules, `environment.packages`, `build.activation`, OpenSSH.

---

### Task 1: Add Declarative SSH Helper

**Files:**
- Create: `nix-on-droid/ssh/authorized_keys`
- Modify: `nix-on-droid/korken.nix`

- [ ] Add `nix-on-droid/ssh/authorized_keys` with the public key used for device access.
- [ ] Add local bindings in `nix-on-droid/korken.nix` for `sshdDirectory`, `authorizedKeys`, and port `8022`.
- [ ] Add `pkgs.openssh` and a generated `sshd-start` script to `environment.packages`.
- [ ] Add `build.activation.sshd` to create `$HOME/.ssh`, copy `authorized_keys`, generate the host key if missing, and write `sshd_config`.
- [ ] Verify with `nix eval`, `nix-instantiate --parse`, commit, push, pull on Android, activate, run `sshd-start`, and SSH back in.
