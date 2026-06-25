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
