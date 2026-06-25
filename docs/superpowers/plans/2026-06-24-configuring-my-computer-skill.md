# configuring-my-computer skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a custom Agent Skill that hands computer-configuration work to a dotfiles-aware subagent, plus the nono grant that lets that subagent write the dotfiles repo from any cwd.

**Architecture:** Two independent changes in the dotfiles repo: (1) a new `skills/configuring-my-computer/SKILL.md` (nix auto-symlinks it into `~/.agents/skills/` via `skills.nix`), (2) one allow-entry in `home/config/nono/profiles/agent.json`. No code, no tests — verification is `nono profile validate`, a frontmatter path-leak grep, and `nixos-rebuild build`.

**Tech Stack:** Markdown (Agent Skill standard), JSON (nono profile), Nix home-manager.

## Global Constraints

- SKILL.md frontmatter `description` MUST NOT contain the dotfiles path or the word "dotfiles". Body may.
- Commit every verified logical change separately (dotfiles `AGENTS.md`).
- Never run `nrs` / `nixos-rebuild switch` — `nixos-rebuild build` only, for verification.
- Source of truth = the spec at `docs/superpowers/specs/2026-06-24-configuring-my-computer-skill-design.md`.

---

### Task 1: nono grant for dotfiles repo

**Files:**
- Modify: `home/config/nono/profiles/agent.json` (the `filesystem.allow` array)

**Interfaces:**
- Produces: write access to `$HOME/projects/dotfiles` inside the agent sandbox from any cwd.

- [ ] **Step 1: Add the allow entry**

In `home/config/nono/profiles/agent.json`, add `"$HOME/projects/dotfiles"` to the `filesystem.allow` array (e.g. right after `"$WORKDIR"`). nono JSON has no comments; record the rationale in the commit message instead.

```json
    "allow": [
      "$WORKDIR",
      "$HOME/projects/dotfiles",
      "$HOME/.claude",
```

- [ ] **Step 2: Validate the profile**

Run: `cd ~/projects/dotfiles && nono profile validate home/config/nono/profiles/agent.json`
Expected: exit 0, no schema errors.

- [ ] **Step 3: Commit**

```bash
cd ~/projects/dotfiles
git add home/config/nono/profiles/agent.json
git commit -m "nono(agent): grant write access to ~/projects/dotfiles

Lets the in-process configuration subagent edit the dotfiles repo from
any cwd. Subagents share the main agent's process-level sandbox, so the
grant must live in the profile (not per-spawn)."
```

---

### Task 2: the configuring-my-computer SKILL.md

**Files:**
- Create: `modules/home-manager/profiles/ai-agents/skills/configuring-my-computer/SKILL.md`

**Interfaces:**
- Consumes: the nono grant from Task 1 (subagent can write dotfiles).
- Produces: a skill auto-discovered by pi at `~/.agents/skills/configuring-my-computer/` after a home-manager switch.

- [ ] **Step 1: Write the file**

Create `modules/home-manager/profiles/ai-agents/skills/configuring-my-computer/SKILL.md` with exactly:

````markdown
---
name: configuring-my-computer
description: "Use when the user wants to configure their computer, system, desktop, or installed programs — changing settings, keybindings, installing software, editing system config — OR when the current task requires such a change or would be made profoundly easier or more elegant by one. Offers to hand the work to a dedicated configuration subagent."
---

# Configuring My Computer

Hand computer-configuration work to a dedicated subagent that carries the
config-repo context, so this session stays focused on its own task.

The config lives in `~/projects/dotfiles` (NixOS + home-manager, git-managed).
That repo's `AGENTS.md` holds the authoritative rules. This session does NOT
read it — that is the subagent's job, and the whole point of the handoff is to
keep that large context out of here.

## When to fire

- The user expresses config intent: "configure my computer", "add this to my
  nixos", "set up program X", "change a keybinding", install software, edit
  system/desktop settings — from any working directory.
- OR the current task requires a config change, or would be made profoundly
  easier or more elegant by one. Recognize the opening and offer the handoff.

## Gate

Ask, using the `question` tool:

> "Spawn a dedicated configuration subagent?"  — options: yes / no

- **no** → step aside; handle the request yourself as usual.
- **yes** → continue below.

## Choose the agent (situational lifecycle)

- If a `dotfiles` subagent already exists AND this request continues related
  work → reuse it (`send_message` to it).
- Otherwise spawn a fresh one named `dotfiles` (or `dotfiles-2`, … if an
  existing one is busy on unrelated work).

## Spawn

`spawn_agent` with this systemPrompt:

```
You are the configuration subagent. You operate ONLY in ~/projects/dotfiles,
a git-managed NixOS + home-manager configuration.

FIRST, before anything else: read ~/projects/dotfiles/AGENTS.md and any nested
AGENTS.md files, and follow them strictly for the rest of this session. They
are the authoritative rules.

You are an in-process agent sharing the parent's working directory, so there is
no persistent `cd`. Use absolute paths and `git -C ~/projects/dotfiles ...`.

Hard rules (also in AGENTS.md):
- Interview one question at a time before non-trivial changes.
- Commit each verified logical change separately; stage individual hunks.
- NEVER run `nrs`, `nixos-rebuild switch`, or any system-activating rebuild.
  `nixos-rebuild build` (no activation) is fine for verification.

Communication: never address the user directly. Send every question to the
agent named `main`, then END YOUR TURN and wait — you are re-woken when `main`
replies. When the work is done, message `main` with a short summary and the
new commit hashes.
```

Deliver as the first message the configuration request, framed with any
relevant current-task context (you are a smart broker, not a pipe).

## Broker the conversation

You hold context the isolated subagent lacks (the current task). Act as an
intelligent intermediary, not a verbatim pipe:
- enrich the subagent's questions with relevant task context before asking the
  user — or answer them yourself when you already know,
- frame the user's answers with that context before relaying them back,
- adapt in both directions.

After each `send_message`, end your turn; you are re-woken on reply.

## On completion

When the subagent reports done, surface to the user:
- the subagent's summary,
- the new commits: `git -C ~/projects/dotfiles log --oneline <before>..HEAD`,
- a reminder: the subagent committed but did not activate — run `nrs` to apply.
````

- [ ] **Step 2: Verify the description does not leak the path**

Run:
```bash
cd ~/projects/dotfiles
awk '/^---$/{n++; next} n==1' modules/home-manager/profiles/ai-agents/skills/configuring-my-computer/SKILL.md | grep -iE 'dotfiles|projects/' && echo "LEAK" || echo "OK: frontmatter path-free"
```
Expected: `OK: frontmatter path-free` (the grep finds nothing in the frontmatter block).

- [ ] **Step 3: Verify the body does name the path (sanity, opposite direction)**

Run: `grep -c 'projects/dotfiles' modules/home-manager/profiles/ai-agents/skills/configuring-my-computer/SKILL.md`
Expected: a number ≥ 3 (body references present).

- [ ] **Step 4: Verify nix wiring builds**

`skills.nix` symlinks every directory under `skills/` automatically — no nix edit needed. Confirm the config still evaluates:

Run: `cd ~/projects/dotfiles && nixos-rebuild build --flake .#$(hostname) 2>&1 | tail -5`
Expected: builds without error (no activation).

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/skills/configuring-my-computer/SKILL.md
git commit -m "skills: add configuring-my-computer handoff skill

Offers to hand config work to a dotfiles-aware subagent; main brokers
the user<->subagent conversation. See spec
docs/superpowers/specs/2026-06-24-configuring-my-computer-skill-design.md."
```

---

## Self-Review

- **Spec coverage:** trigger (Task 2 frontmatter + "When to fire") ✓; question gate ✓; situational lifecycle ✓; spawn systemPrompt with AGENTS.md-first + no-nrs + relay ✓; smart-broker communication ✓; completion summary + commits + nrs reminder ✓; nono pre-grant (Task 1) ✓; path-free description (Step 2 check) ✓; files match spec ✓.
- **Placeholder scan:** none — full SKILL.md and JSON content inlined.
- **Type consistency:** agent name `dotfiles`/`main`, tool names `question`/`spawn_agent`/`send_message` consistent across plan and SKILL body.

## Execution note

After Task 2 Step 4 builds, the skill only becomes live in pi after the user runs `nrs` (manual) and `/reload` in pi. Do not run `nrs` — surface it as the final manual step.
