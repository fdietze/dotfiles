# `set-session-name` pi extension design

## Problem

Running multiple pi instances in separate kitty tabs / niri windows, there is no
glanceable way to tell what each one is working on. The terminal title (read by
both kitty tabs and the noctalia/niri active-window bar) defaults to
`pi - <cwd>`, which only distinguishes by project, not by task.

## Goal

Give the AI a tool to label the current session with a short (2-word) phrase
describing the main task. The label drives the terminal title so a glance at the
kitty tab or niri bar tells you what each pi instance is doing.

## Decisions

- **Mechanism: `pi.setSessionName(name)`**, not bare `ctx.ui.setTitle()`.
  Single source of truth. Pi owns title rendering: setting the session name emits
  `session_info_changed`, and pi rebuilds the terminal title as
  `pi - <name> - <cwd>` (traced in `agent-session.js:2155`,
  `interactive-mode.js:526`). Bonus: the name persists in the session file and
  shows in the session selector + footer.

- **Title format is decorated, not bare.** Result is e.g.
  `pi - fix parser - dotfiles`. The 2 words are the variable middle; `pi -` and
  `- <cwd>` are fixed decoration that usefully identify pi + project in the bar.
  Accepted over a bare-2-word title because the bare path requires fighting pi's
  own title machinery (clobbered on reload/new/resume) and gains no persistence.

- **No clobber war, so no event handlers.** Pi has no session auto-naming;
  `session_info_changed` / `updateTerminalTitle` fire only on an explicit
  name-set or a session lifecycle event (reload/new/resume), and those rebuild
  the title correctly from the stored name. A `turn_end` re-assert hook was
  considered and dropped (YAGNI) once tracing proved no clobber occurs.

- **Param: single string `name`, 2 words by guidance, no enforcement.**
  Passed straight to `pi.setSessionName`, which sanitizes (strips newlines,
  trims; `session-manager.js:747` — spaces preserved). Word-count enforcement
  (two params / truncate / reject) rejected: guidance is enough, and structural
  enforcement costs either AI retry turns or silent data loss.

- **Proactive use via prompt injection.** `promptSnippet` + `promptGuidelines`
  are injected into the system prompt while the tool is active, nudging the AI to
  relabel when the session's main topic/job/task changes — so the bar tracks the
  current focus without manual prompting.

- **Naming: `set-session-name` / `setSessionName`.** Names exactly what the tool
  does (sets the pi session name, which in turn drives the title), per the
  filesystem-as-semantic-index principle.

## Implementation

Single file `modules/home-manager/profiles/ai-agents/pi-extensions/set-session-name.ts`,
auto-symlinked into `~/.pi/agent/extensions/` by `pi-extensions.nix`.

```typescript
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "setSessionName",
    label: "Set Session Name",
    description:
      "Set the pi session name (2 words) labeling the current main task. " +
      "Pi renders it into the terminal title as 'pi - <name> - <cwd>', " +
      "visible in the kitty tab and the niri/noctalia active-window bar.",
    promptSnippet: "Set a 2-word session name labeling the current main task",
    promptGuidelines: [
      "Call setSessionName with 2 words whenever the session's main topic/job/task changes, to relabel the window.",
    ],
    parameters: Type.Object({
      name: Type.String({ description: "Two words summarizing the current main task" }),
    }),
    async execute(_toolCallId, params) {
      pi.setSessionName(params.name);
      return {
        content: [{ type: "text", text: `Session name set: "${params.name}"` }],
        details: {},
      };
    },
  });
}
```

No event handlers; the factory only registers the tool.

## Activation

Edit the `.ts` in the repo → home-manager switch (symlink already wired by
`pi-extensions.nix`) → `/reload` in pi to hot-load.

## Principles applied

- **Functional core / imperative shell:** tool body delegates to pi's own title
  machinery; no parallel title state in the extension.
- **YAGNI / KISS:** dropped the re-assert hook, word-count enforcement, and
  bare-title override after tracing pi internals proved them unnecessary.
- **Single source of truth:** session name is the one input; pi derives the title.
- **Filesystem as semantic index:** file + tool named for exactly what they do.
