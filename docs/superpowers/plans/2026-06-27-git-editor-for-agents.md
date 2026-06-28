# GIT_EDITOR=true for AI Agents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inject `GIT_EDITOR=true` and `GIT_SEQUENCE_EDITOR=true` into the AI agent wrapper configuration to prevent interactive git editors from blocking programmatic agent executions.

**Architecture:** Inject these exports into the shell script generator function `mkAgent` within the Nix configuration.

**Tech Stack:** Nix, NixOS

## Global Constraints

- Modify only the designated AI agent Nix wrapper code.
- Apply to both sandboxed and vanilla agents.

---

### Task 1: Update Agent Wrappers and Verify Build

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/default.nix`

**Interfaces:**
- Consumes: None
- Produces: None

- [ ] **Step 1: Edit agent script template in Nix configuration**

Edit `modules/home-manager/profiles/ai-agents/default.nix` to export `GIT_EDITOR=true` and `GIT_SEQUENCE_EDITOR=true` inside `mkAgent`.

```nix
  mkAgent = {
    name,
    bin,
    env ? "",
    yolo ? "",
  }: [
    (pkgs.writeShellScriptBin name ''
      export GIT_EDITOR=true
      export GIT_SEQUENCE_EDITOR=true
      ${env}exec ${prio} ${privateTmp} \
        ${pkgs.llm-agents.nono}/bin/nono wrap --profile agent -- \
        ${bin}${lib.optionalString (yolo != "") " ${yolo}"} "$@"
    '')
    (pkgs.writeShellScriptBin "vanilla-${name}" ''
      export GIT_EDITOR=true
      export GIT_SEQUENCE_EDITOR=true
      ${env}exec ${prio} \
        ${bin} "$@"
    '')
  ];
```

- [ ] **Step 2: Run dry-build of the NixOS configuration to verify correctness**

Verify that the Nix configuration compiles and has no syntax or evaluation errors.

Run:
```bash
nix-shell -p nixos-rebuild --run "nixos-rebuild build --flake .#$(hostname)"
```

Expected output: Evaluates and builds the system toplevel successfully without any syntax or type errors.

- [ ] **Step 3: Commit the changes**

Run:
```bash
git add modules/home-manager/profiles/ai-agents/default.nix
git commit -m "feat(ai-agents): inject GIT_EDITOR=true into agent environment"
```
