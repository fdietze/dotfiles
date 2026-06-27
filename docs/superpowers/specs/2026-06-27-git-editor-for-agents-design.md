# GIT_EDITOR=true for AI Agents

## Problem

AI agents (like `claude`, `opencode`, `codex`, `pi`) running in sandboxed or vanilla environments frequently get stuck when executing git commands that require interactive user input.

- **Example 1:** During `git rebase --continue` (after conflict resolution), Git opens the configured terminal text editor (e.g., `nano`, `vim`, `helix`) to let the user review/edit the commit message.
- **Example 2:** `git rebase -i` opens the editor to edit the todo list.
- **Example 3:** Standard `git commit` without `-m` opens an editor.

Because the agent runs commands programmatically in non-interactive shells, stdin/stdout are redirected and no terminal is attached. The launched editor hangs indefinitely waiting for input, blocking the agent shell execution. The agent is stuck and eventually times out or wastes turns.

## Decision

Configure the agent execution environment to use a non-interactive, immediately-exiting dummy editor for all git tasks.

Set the following environment variables globally inside all AI agent wrappers:
- `GIT_EDITOR=true` (forces git to use `/bin/true` as the editor, instantly exiting successfully with code 0, using the default commit message/template without blocking)
- `GIT_SEQUENCE_EDITOR=true` (forces git to use `/bin/true` for editing the todo list during interactive rebases)

These variables override any user-configured `$EDITOR`, `$VISUAL`, `core.editor`, or `sequence.editor` git configuration options, but *only* within the environment of the AI agents. The human user's interactive terminal is completely unaffected.

## Implementation Plan

### 1. Update Launcher Script
Modify `modules/home-manager/profiles/ai-agents/default.nix` in the `mkAgent` function to export these variables:

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

### 2. Verify
1. Run `nixos-rebuild build` to verify the Nix configuration builds cleanly.
2. The user will run the rebuild / activation manually.
