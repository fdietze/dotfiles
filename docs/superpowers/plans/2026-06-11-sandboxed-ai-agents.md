# Sandboxed AI-Agents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Abstract the nono-sandbox AI-agent wrappers into a reusable `mkAgent` helper in a dedicated module, add `codex` and `pi` agents, and move the shared nono profile into the repo (renamed `claude` → `agent`) as an out-of-store symlink.

**Architecture:** New module `modules/home-manager/profiles/ai-agents.nix` holds a `let`-bound `mkAgent` helper that emits a sandboxed `<name>` wrapper plus a `vanilla-<name>` escape hatch per agent. The current inline wrappers move out of `packages-cli.nix`. The nono profile JSON lives in `home/config/nono/profiles/agent.json`, symlinked into place via `config.lib.file.mkOutOfStoreSymlink`.

**Tech Stack:** Nix, Home-Manager (as NixOS module), `pkgs.writeShellScriptBin`, nono sandbox, nvd for diff verification.

---

## Background facts (verified during design)

- Host: `gurke`. Active specialisation: `noctalia-niri`.
- Binary names (`meta.mainProgram`): `claude-code`→`claude`, `opencode`→`opencode`, `codex`→`codex`, `pi-coding-agent`→`pi`.
- yolo / skip-permission flags (verified against each binary's `--help`):
  - `claude`: `--dangerously-skip-permissions`
  - `opencode`: **none** (matches current wrapper)
  - `codex`: `--dangerously-bypass-approvals-and-sandbox` ("Intended solely for running in environments that are externally sandboxed" — exactly our nono case)
  - `pi`: **none** (pi's bash/edit/write tools run directly; no approval-gating flag exists)
- nono `--profile` accepts a name OR a path; resolves names from `~/.config/nono/profiles/`.
- The current `claude` user profile lives at `~/.config/nono/profiles/claude.json`, `extends default`, already agent-generic (`"description": "general AI agent sandbox"`).

## Verification primitives (used throughout)

Build the Home-Manager profile derivation (no activation, pre-switch):

```bash
nix build .#nixosConfigurations.gurke.config.home-manager.users.felix.home.path -o /tmp/hm-<label>
```

- Wrapper script content: `cat /tmp/hm-<label>/bin/<wrapper>`
- Store-path diff between two builds: `nvd diff /tmp/hm-<before> /tmp/hm-<after>`

A current baseline already exists at `/tmp/hm-baseline` (built before any edits). If it is gone, rebuild it from a clean checkout of the current `HEAD` before starting Task 1.

## File Structure

- **Create** `modules/home-manager/profiles/ai-agents.nix` — `mkAgent` helper, the four agents, the nono-profile symlink. Owns the sandboxed-agent concern.
- **Create** `home/config/nono/profiles/agent.json` — the relocated nono profile (verbatim copy of the old `claude.json`, `meta.name` → `agent`).
- **Modify** `modules/home-manager/profiles/packages-cli.nix` — remove the four inline wrapper blocks and the `++ [ ... ]` concatenation; keep the plain package list (incl. `nono`, `bubblewrap`).
- **Modify** `modules/home-manager/profiles/shell-core.nix` — add `./ai-agents.nix` to `imports`.

---

## Task 1: Extract claude + opencode wrappers into `ai-agents.nix` (byte-identical no-op)

This task is a pure refactor. The generated wrapper scripts must be **byte-for-byte identical** to the current ones (still `--profile claude`), so `nvd diff` shows **zero changes**. The profile rename and new agents come in later tasks. This follows the CLAUDE.md rule: do the enabling refactor first, verify with nvd, commit it separately.

**Files:**
- Create: `modules/home-manager/profiles/ai-agents.nix`
- Modify: `modules/home-manager/profiles/packages-cli.nix` (remove lines 109-140, the `++ [ ... ]` block)
- Modify: `modules/home-manager/profiles/shell-core.nix` (imports list, ~line 18-24)

- [ ] **Step 1: Create `ai-agents.nix` reproducing the current wrappers exactly**

The `mkAgent` template is carefully shaped to reproduce the existing multi-line layout (continuation backslashes, 2-space indent on continued lines, single space before `"$@"`). Note `--profile claude` is intentional in THIS task — it changes to `agent` in Task 2.

Create `modules/home-manager/profiles/ai-agents.nix`:

```nix
# Sandboxed AI coding agents. Each agent gets a nono-wrapped `<name>` plus an
# un-sandboxed `vanilla-<name>` escape hatch, both at low CPU/IO priority. The
# shared nono profile `agent` is sourced from the repo via out-of-store symlink
# so it stays versioned yet live-editable without a Home-Manager switch.
{
  config,
  lib,
  pkgs,
  ...
}: let
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";

  # Low CPU/IO priority so agent subprocesses don't starve interactive work.
  prio = "${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19";

  # Wrap an AI coding agent.
  #   env  -> shell prelude (export lines, must end in "\n"); applied to BOTH variants
  #   yolo -> flag(s) that disable the agent's own permission prompts; sandboxed
  #           variant ONLY — without nono (vanilla) we keep the agent's prompts.
  mkAgent = {
    name,
    bin,
    env ? "",
    yolo ? "",
  }: [
    (pkgs.writeShellScriptBin name ''
      ${env}exec ${prio} \
        ${pkgs.nono}/bin/nono run --profile claude -- \
        ${bin}${lib.optionalString (yolo != "") " ${yolo}"} "$@"
    '')
    (pkgs.writeShellScriptBin "vanilla-${name}" ''
      ${env}exec ${prio} \
        ${bin} "$@"
    '')
  ];
in {
  home.packages = lib.concatLists [
    # `claude`: experimental agent-teams env + skip its own permission prompts
    # (nono is the real isolation layer). `vanilla-claude` keeps the prompts.
    (mkAgent {
      name = "claude";
      bin = "${pkgs.claude-code}/bin/claude";
      env = "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1\n";
      yolo = "--dangerously-skip-permissions";
    })
    (mkAgent {
      name = "opencode";
      bin = "${pkgs.opencode}/bin/opencode";
    })
  ];
}
```

- [ ] **Step 2: Remove the inline wrappers from `packages-cli.nix`**

In `modules/home-manager/profiles/packages-cli.nix`, delete the entire `++ [ ... ]` block (the four `writeShellScriptBin` definitions for `claude`, `vanilla-claude`, `opencode`, `vanilla-opencode`) so the file ends with just the package list. The result must be:

```nix
{pkgs, ...}: {
  home.packages = with pkgs; [
    # shell / TUI essentials
    tmux
    # ... (unchanged full list) ...
    markdownlint-cli2
    rtk
  ];
}
```

Concretely: remove the closing `)` + `++ [` ... `]` wrapper. Change line 2 from `(with pkgs; [` back to `with pkgs; [`, remove the `])` on the old line 108, delete old lines 109-140, and keep the final `}`. Keep `bubblewrap` and `nono` in the list.

- [ ] **Step 3: Import `ai-agents.nix` from `shell-core.nix`**

In `modules/home-manager/profiles/shell-core.nix`, add `./ai-agents.nix` to the `imports` list:

```nix
  imports = [
    ../shell.nix
    ../dotfiles.nix
    ../git.nix
    ../yazi.nix
    ./packages-cli.nix
    ./ai-agents.nix
  ];
```

- [ ] **Step 4: Build the HM profile**

Run:
```bash
nix build .#nixosConfigurations.gurke.config.home-manager.users.felix.home.path -o /tmp/hm-task1
```
Expected: builds successfully, exit 0.

- [ ] **Step 5: Verify the wrappers are byte-identical (nvd zero diff)**

Run:
```bash
nvd diff /tmp/hm-baseline /tmp/hm-task1
```
Expected: `<<< No package changes >>>` (or equivalent empty diff). If any wrapper store path changed, the template formatting drifted — diff `cat /tmp/hm-baseline/bin/claude` against `cat /tmp/hm-task1/bin/claude` and fix whitespace until identical.

- [ ] **Step 6: Commit**

```bash
git add modules/home-manager/profiles/ai-agents.nix \
        modules/home-manager/profiles/packages-cli.nix \
        modules/home-manager/profiles/shell-core.nix
git commit -m "refactor(ai-agents): extract sandboxed-agent wrappers into mkAgent helper

Byte-identical no-op: claude/opencode wrappers unchanged (verified via nvd).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Move nono profile into repo, rename `claude` → `agent`

**Files:**
- Create: `home/config/nono/profiles/agent.json`
- Modify: `modules/home-manager/profiles/ai-agents.nix` (profile string + symlink)

- [ ] **Step 1: Copy the profile verbatim into the repo**

Use a shell copy to preserve the file exactly (no copy-paste):
```bash
mkdir -p home/config/nono/profiles
cp ~/.config/nono/profiles/claude.json home/config/nono/profiles/agent.json
```

- [ ] **Step 2: Rename the profile inside the copied file**

Edit `home/config/nono/profiles/agent.json` — change only the `meta.name` field:
```json
  "meta": {
    "name": "agent",
    "version": "1.0.0",
    "description": "general AI agent sandbox",
    "author": "felix"
  },
```
Leave every other field unchanged.

- [ ] **Step 3: Switch the wrapper to `--profile agent` and add the symlink**

In `modules/home-manager/profiles/ai-agents.nix`:

Change the sandboxed line in `mkAgent` from `--profile claude` to `--profile agent`:
```nix
        ${pkgs.nono}/bin/nono run --profile agent -- \
```

Add the out-of-store symlink to the module's attribute set (alongside `home.packages`):
```nix
  # Source the shared nono profile from the repo (versioned) while keeping it
  # live-editable without a HM switch. nono resolves `--profile agent` by name
  # from ~/.config/nono/profiles/.
  home.file.".config/nono/profiles/agent.json".source =
    config.lib.file.mkOutOfStoreSymlink "${repoDir}/home/config/nono/profiles/agent.json";
```

- [ ] **Step 4: Build the HM profile**

Run:
```bash
nix build .#nixosConfigurations.gurke.config.home-manager.users.felix.home.path -o /tmp/hm-task2
```
Expected: builds successfully, exit 0.

- [ ] **Step 5: Verify the expected changes**

Run:
```bash
nvd diff /tmp/hm-task1 /tmp/hm-task2
cat /tmp/hm-task2/bin/claude
cat /tmp/hm-task2/bin/opencode
```
Expected: nvd shows the `claude` and `opencode` wrapper packages changed (their script now says `--profile agent`). The `cat` output must show `nono run --profile agent -- ...`. `vanilla-*` wrappers unchanged.

Note: the `home.file` symlink is NOT part of the `home.path` build derivation (it is a separate activation mechanism), so it cannot be verified from `/tmp/hm-task2`. The symlink is verified post-switch in the final verification section. To eval-check it pre-switch, run:
```bash
nix eval --raw .#nixosConfigurations.gurke.config.home-manager.users.felix.home.file.'".config/nono/profiles/agent.json"'.source
```
Expected: a path ending in `projects/dotfiles/home/config/nono/profiles/agent.json`.

- [ ] **Step 6: Commit**

```bash
git add home/config/nono/profiles/agent.json \
        modules/home-manager/profiles/ai-agents.nix
git commit -m "feat(ai-agents): move nono profile into repo, rename claude -> agent

Profile now versioned at home/config/nono/profiles/agent.json and symlinked
via mkOutOfStoreSymlink; all agent wrappers use --profile agent.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 7: Note the manual cleanup (do NOT do it now)**

After the user runs `nrs` (switch), the stale `~/.config/nono/profiles/claude.json` becomes orphaned. Record in the final handoff that the user should `rm ~/.config/nono/profiles/claude.json` once the switched system works. Different filename → no HM clobber, so it is safe to leave until then.

---

## Task 3: Add `codex` and `pi` agents

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents.nix` (two more `mkAgent` calls)

- [ ] **Step 1: Add the two agents to `home.packages`**

In `modules/home-manager/profiles/ai-agents.nix`, append to the `lib.concatLists [ ... ]` list:

```nix
    # `codex`: bypass codex's own approvals + built-in sandbox; nono is the
    # external sandbox the flag is designed for. `vanilla-codex` keeps approvals.
    (mkAgent {
      name = "codex";
      bin = "${pkgs.codex}/bin/codex";
      yolo = "--dangerously-bypass-approvals-and-sandbox";
    })
    # `pi`: no permission-gating flag exists; its tools run directly under nono.
    (mkAgent {
      name = "pi";
      bin = "${pkgs.pi-coding-agent}/bin/pi";
    })
```

- [ ] **Step 2: Build the HM profile**

Run:
```bash
nix build .#nixosConfigurations.gurke.config.home-manager.users.felix.home.path -o /tmp/hm-task3
```
Expected: builds successfully, exit 0.

- [ ] **Step 3: Verify the new wrappers exist with correct content**

Run:
```bash
nvd diff /tmp/hm-task2 /tmp/hm-task3
cat /tmp/hm-task3/bin/codex
cat /tmp/hm-task3/bin/pi
cat /tmp/hm-task3/bin/vanilla-codex
cat /tmp/hm-task3/bin/vanilla-pi
```
Expected: nvd shows 4 packages added (`codex`, `vanilla-codex`, `pi`, `vanilla-pi`). `codex` wrapper contains `nono run --profile agent -- <codex> --dangerously-bypass-approvals-and-sandbox "$@"`. `pi` wrapper contains `nono run --profile agent -- <pi> "$@"` (no yolo flag, single space before `"$@"`). `vanilla-codex` and `vanilla-pi` run the binaries directly without nono and without yolo flags.

- [ ] **Step 4: Confirm no PATH collisions**

Run:
```bash
ls /tmp/hm-task3/bin | grep -E '^(codex|pi|opencode|claude)$'
```
Expected: exactly one entry each — the wrappers, not the raw packages. (`codex`, `pi-coding-agent`, `opencode`, `claude-code` must NOT be in the plain `packages-cli.nix` list.)

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents.nix
git commit -m "feat(ai-agents): add codex and pi sandboxed agents

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (after user runs `nrs noctalia-niri`)

These require activation and are the user's manual step; list them in the handoff:

- [ ] `nono profile list` shows `agent` under user profiles (and no longer relies on `claude`).
- [ ] `nono profile validate ~/.config/nono/profiles/agent.json` passes.
- [ ] `realpath ~/.config/nono/profiles/agent.json` points into `~/projects/dotfiles/home/config/nono/profiles/agent.json` (out-of-store).
- [ ] `command -v codex pi claude opencode` all resolve to the wrapper scripts.
- [ ] Smoke-run each agent (`codex`, `pi`, `claude`, `opencode`) and a `vanilla-*` variant.
- [ ] Remove the orphaned old profile: `rm ~/.config/nono/profiles/claude.json`.
```
