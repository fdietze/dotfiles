# configuring-my-computer skill — design

## Problem

Editing the dotfiles repo from inside an unrelated project session pollutes the
main agent's context with the large `~/projects/dotfiles/AGENTS.md` (+ nested
AGENTS.md files) and config exploration. We want config work handed to a
dedicated subagent that carries the dotfiles context, while the main session
stays focused on its own task.

## Goal

A custom Agent Skill that, when the user wants to configure their
computer/system/desktop/programs — or when the current task would be made
profoundly easier by a config change — offers to spawn a dotfiles-aware
configuration subagent and brokers the conversation between user and subagent.

## Trigger (path-free description)

Fires on:
- explicit config intent — "configure my computer", "add this to my nixos",
  "set up program X", "change keybinding", install software, edit system config;
  from **any** cwd, and
- proactively, when the current task **requires** a config change or would be
  made profoundly easier / more elegant by one (main recognizes the opening).

The SKILL.md frontmatter `description` MUST NOT reveal the dotfiles path or the
word "dotfiles". The body may name `~/projects/dotfiles` freely.

## Flow

1. Skill fires → main asks via the `question` tool:
   *"Spawn a dedicated configuration subagent?"* `[yes / no]`.
   - **no** → skill steps aside; main handles the request itself, normally.
   - **yes** → continue.

2. **Lifecycle — situational.** If a `dotfiles` subagent already exists and the
   new request continues related work → reuse it (`send_message`). Otherwise
   spawn fresh (`dotfiles`, or `dotfiles-2`… when an existing one is busy on
   unrelated work). Main judges relatedness.

3. **Spawn** the subagent with a systemPrompt establishing:
   - Role = configuration subagent operating in `~/projects/dotfiles`.
   - **First action:** read `~/projects/dotfiles/AGENTS.md` (and nested
     `AGENTS.md`) and follow them strictly. Operate via absolute paths and
     `git -C ~/projects/dotfiles` — it is an in-process agent sharing main's
     cwd, so there is no persistent `cd`.
   - Obey the dotfiles rules: interview one question at a time, commit each
     verified logical change (stage individual hunks), and **never** run `nrs`
     / `nixos-rebuild switch` (`nixos-rebuild build` for verification only).
   - **Relay rule:** never address the user directly. Send every question to
     `main`, then end the turn and wait (event-driven re-wake).
   - On completion: message `main` with a summary + the new commit hashes.
   - **First delivered message** = the config request, framed by main with
     relevant current-task context.

4. **Communication — smart broker (not verbatim).** Main is an intelligent
   intermediary, not a pipe. It holds context the isolated subagent lacks (the
   current task), so it:
   - enriches the subagent's questions with relevant task context before asking
     the user — or answers them itself when it already knows,
   - frames the user's answers with that context before relaying back,
   - adapts in both directions.
   After each send, main ends its turn (re-woken on reply).

5. **Completion.** Main surfaces to the user: the subagent's summary + a
   `git -C ~/projects/dotfiles log` of the new commits + a reminder to run `nrs`
   to apply (the subagent commits but, per dotfiles rules, never activates).

## Sandbox (separate change, same repo)

pi subagents run **in-process**, sharing the main agent's nono sandbox
(process-level). To let the subagent write the dotfiles repo from any cwd, add
`$HOME/projects/dotfiles` to `filesystem.allow` in
`home/config/nono/profiles/agent.json`, with a comment explaining why.

Runtime capability-elevation prompts were rejected: nono's only escalation UX
writes to `/dev/tty`, which is unusable mid-session under pi's raw-mode
alt-screen TUI. Static pre-grant is the simple, working choice.

## Files

- `modules/home-manager/profiles/ai-agents/skills/configuring-my-computer/SKILL.md`
  — nix auto-symlinks every `skills/<name>/` dir into `~/.agents/skills/` via
  `skills.nix`.
- edit `home/config/nono/profiles/agent.json` — add the allow entry.

## Out of scope

- Runtime per-access approval UX (rejected above).
- Any change to the subagents pi-extension.
- Multi-repo / non-dotfiles config targets.
