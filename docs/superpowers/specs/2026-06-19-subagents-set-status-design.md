# Subagents `set_status` tool design

## Problem

Background agents have no way to communicate a semantic, self-described status.
`list_agents`, the `/agents` panel, and the roster widget only show the
system-derived status (`spawning | idle | thinking | writing | tool:<name> |
halted`), computed from streaming state + activity phase. An agent parsing 500
files or blocked waiting on a peer cannot signal *what* it is doing without a
peer calling `agent_history`.

## Goal

Give background agents a tool to set a short status phrase. It appears appended
to the system status everywhere the agent row is rendered: the `list_agents`
tool output (for other agents), and the `/agents` panel + persistent roster
widget (for the human). One source of truth, consistent display.

## Decisions

- **Consumer: both** agents and human. Status appears in every render site.
- **Relation to system status: append.** `thinking · parsing files`, `idle ·
  waiting for review`. System status stays authoritative about runtime state;
  custom status adds semantic context. Combined only at render time — NOT inside
  `statusLabel()`, which stays system-status-only so `isBusy()` keys off the real
  runtime state (an idle agent with a custom status must not read as busy). The
  custom status is capped to ~20 chars (prompt guidance + hard ellipsis at the
  28-char roster column).
- **Interface: simple setter.** `set_status({ status })`. Empty string clears.
  No TTL, no progress, no structured phases (YAGNI). Staleness is already
  observable via the `halted` status + `last activity` age.
- **Scope: background agents only.** Main has `ctx.ui.setStatus()` for the
  footer and is directly observed by the human. Adding another status channel
  for main creates confusion.

## Approach

Engine-level field + tool in `makeAgentTools()`, with main excluded at
registration. Minimal change, fits existing architecture.

### 1. Engine (`engine.ts`)

Add to `AgentRecord`:

```typescript
customStatus?: string;  // agent-set semantic status, appended to system status
```

Add method to `Engine`:

```typescript
setCustomStatus(name: string, status: string | undefined): void {
  const rec = this.agents.get(name);
  if (rec) rec.customStatus = status || undefined;  // empty string -> clear
}
```

Modify `statusLabel()` to append. Its `Pick<>` param type must add
`"customStatus"`:

```typescript
export function statusLabel(
  rec: Pick<AgentRecord, "pending" | "streaming" | "activity" | "currentTool" | "halted" | "customStatus">,
): string {
  const base = rec.pending ? "spawning"
    : rec.halted ? "halted"
    : !rec.streaming ? "idle"
    : rec.activity === "tool" ? (rec.currentTool ? `tool:${rec.currentTool}` : "tool")
    : rec.activity === "writing" ? "writing"
    : "thinking";
  return rec.customStatus ? `${base} · ${rec.customStatus}` : base;
}
```

Because `statusLabel()` is the single source of truth for status, all three
render sites (`formatSnapshot` in feed.ts, the roster widget, the panel) pick up
the appended status automatically — no further changes there.

### 2. Tool (`index.ts`, in `makeAgentTools(selfName)`)

```typescript
{
  name: "set_status",
  label: "Set Status",
  renderCall: (args, theme) => renderToolArgs("set_status", args as Record<string, unknown>, theme as RenderTheme),
  description:
    "Set your short status line shown in list_agents and the agents panel " +
    "(e.g. 'parsing 500 files', 'waiting on review'). Pass empty string to clear. " +
    "Keep it short — one phrase. Update it when your phase changes.",
  parameters: Type.Object({
    status: Type.String({ description: "Short status phrase; empty clears" }),
  }),
  execute: async (_id, args) => {
    engine.setCustomStatus(selfName, args.status);
    updateStatus();
    return {
      content: [{ type: "text", text: args.status ? `status set: ${args.status}` : "status cleared" }],
      details: {},
    };
  },
}
```

### 3. Exclude main at registration

`makeAgentTools` is called in two places. Background agents (`customTools:
makeAgentTools(spec.name)`) keep all tools. The foreground main loop filters
`set_status` out:

```typescript
for (const tool of makeAgentTools("main")) {
  if (tool.name === "set_status") continue;  // background-only
  pi.registerTool(tool);
}
```

### 4. System prompt (`agentSystemPrompt()`)

Add one line to the tool list:

```
- set_status({status}): set your short status line (shown to others in list_agents); empty string clears.
```

## Testing

- `engine.test.ts`: `setCustomStatus` sets + clears (empty string → undefined),
  no-op on unknown name.
- `statusLabel` (wherever tested, e.g. engine.test.ts): base status alone when no
  custom status; `base · custom` when set; clears back to base.

## Out of scope

- TTL / auto-expiry of stale status.
- Structured status (phase/detail/progress).
- Status for main.
- Persisting custom status to roster.json (in-memory only; resets on restart,
  consistent with other live runtime state).
