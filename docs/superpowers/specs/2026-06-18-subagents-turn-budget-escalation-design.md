# Subagents turn-budget escalation + clean halt

Date: 2026-06-18
Extension: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/`

## Problem

The global turn budget is a silent kill. When `turnsUsed >= turnBudget`,
`recordTurnStart` returns `abort:true` and `subscribeBackground` calls
`session.abort()` — but the engine is **not** frozen, **no** event is emitted, and
**no one is notified**. Each background agent dies individually at its next
`turn_start`. The `main` agent never learns. Recovery requires a human typing
`/unhalt`.

Two further defects:

1. The abort cuts the turn the agent *wanted* to take (mid-write / about to call a
   tool), wasting in-progress work, instead of letting the current turn finish and
   only blocking the next one.
2. The budget (`used/total`) is only visible inside the `/agents` panel header, not
   in the persistent roster widget shown when the panel is closed.

## Goals

- Raise the budget 100 → 200.
- On budget exhaustion, freeze the whole swarm and **escalate to `main`** so the
  main agent decides whether the group continues.
- Stop agents at clean turn boundaries (finish current turn, block the next) rather
  than aborting mid-turn.
- Give a per-agent **`halted`** status distinct from `idle`, so resume re-triggers
  only the interrupted agents.
- `main` resumes with a single `resume_agents()` tool call; no per-agent "continue"
  messaging by main.
- Always show the budget at a glance in the persistent widget.

## Non-goals

- Auto-replaying the exact interrupted action with custom per-action machinery
  (rejected: model context already tells it what to redo — one fixed nudge suffices).
- Per-extension tool allowlisting for subagents.
- Eliminating the residual dangling-`tool_use` risk (not possible without an
  unexposed SDK hook; mitigated + verified instead — see Risks).

## Background: turn semantics (verified in `pi-agent-core/dist/agent-loop.js`)

- A **turn** = one LLM round-trip: one assistant message + execution of its tool
  calls. `turn_start`/`turn_end` bracket each round.
- A delivered message (`prompt()`) brackets as
  `agent_start … (turn_start/turn_end)* … agent_end` — one message can span many
  turns until the model stops calling tools.
- `recordTurnStart` fires on every `turn_start`, so the budget counts **LLM rounds
  across all background agents**. 200 = 200 LLM calls.
- The agent loop has `config.shouldStopAfterTurn`, checked after `turn_end` and
  before the next `turn_start` — a clean stop with no abort. **It is NOT exposed**
  through `createAgentSession` (`AgentOptions` exposes `prepareNextTurn`/
  `beforeToolCall`/`afterToolCall` only). The single reachable lever on a background
  session is `session.abort()`.

## Design

### 1. Budget constant

`CAPS.turnBudget` 100 → **200**.

### 2. Freeze-by-blocking (no mid-turn abort)

Change `recordTurnStart` so the budget-crossing turn is **allowed to complete**:

- On the `turn_start` whose increment reaches the limit: increment, set
  `frozen = true`, `frozenReason = "budget"`, emit the halt event, and return
  `abort:false` (let this turn finish).
- Any subsequent `turn_start` (engine already `frozen`) returns `abort:true` →
  `subscribeBackground` calls `session.abort()`, blocking that next turn.

Net effect:

- Every agent completes the turn whose `turn_start` already fired.
- New turns are blocked everywhere.
- Budget overshoots by ≤ (#active agents) turns — bounded, acceptable.
- The budget is evaluated only at turn boundaries, so the budget path never cuts an
  agent mid-tool / mid-write.

Manual `/halt` keeps aborting immediately (`frozenReason = "manual"`) — the human
asked for an immediate stop. Its in-flight agents are cut mid-turn; they are marked
`halted` by the same rule below so `/unhalt` re-nudges them.

### 3. Single `halted` swarm state, two causes

Engine: add `frozenReason?: "manual" | "budget"`. `resume()` clears `frozen` and
`frozenReason`, resets `turnsUsed` to 0. `swarmStateLine` stays
`⏸ halted — /unhalt to resume`; the *why* travels in the escalation message, not the
status word.

### 4. Per-agent `halted` status

`statusLabel` gains `halted`. **Marking rule (cause-agnostic):** at `halt()` time,
mark every agent that is currently `streaming` as `halted`; non-streaming (`idle`)
agents are left alone. This captures both paths uniformly — manual `/halt` (agents
aborted mid-turn) and budget freeze (crossing turn completes, next blocked) — without
depending on abort timing or events.

`halted` is a dedicated boolean flag on `AgentRecord`. It must survive the natural
`agent_end` of an allowed-to-complete turn: `setStreaming(name, false)` resets
`activity`/`currentTool` but must NOT clear `halted`. Only `resume()` clears it (after
the nudge). A false-positive (an agent that was streaming but had actually finished)
just gets a harmless no-op nudge — acceptable (KISS).

`statusLabel` precedence: `spawning` → `halted` → (`tool:`/`writing`/`thinking` while
streaming) → `idle`.

### 5. `resume_agents()` tool (main-only) + `/unhalt`

- New tool `resume_agents()`, registered **only for `main`** (via the
  `pi.registerTool` loop in `index.ts`), NOT in `makeAgentTools` given to background
  agents — only main decides whether the group continues.
- Behavior (shared with `/unhalt`): collect the `halted` agents, call
  `engine.resume()` (unfreeze + re-arm budget to 0 + clear `halted` flags), then fire
  a **fixed internal nudge** (`[resumed] continue your interrupted work`) to the
  collected agents. Resume must precede the nudge because `route()` rejects delivery
  while `frozen`. `idle` agents are untouched.
- `/unhalt` keeps working for the human and now also performs the nudge step.

### 6. Escalation to `main` on budget-halt

`index.ts` already subscribes to engine events. Change the subscriber to inspect the
event: on `halt` with `reason === "budget"`, deliver one message to `main` via the
existing `deliverToMain` sink (wrapped in try/catch; the halt event fires exactly
once because the `frozen` guard prevents re-entry):

> turn budget (200) exhausted, swarm halted. resume_agents() to re-arm and continue.
> If turns ran higher than expected, inspect with list_agents before resuming.

Manual `/halt` does NOT escalate (human initiated it).

### 7. Persistent widget budget header

`updateStatus` in `index.ts` currently renders roster rows + the halted/live state
line only. Prepend the same header the `/agents` panel shows:
`─ agents · N agents · M running · budget U/T ─`. Budget becomes always visible.

## Events / vocabulary changes

- `AgentEvent` `halt` variant gains `reason: "manual" | "budget"`.
- Engine: new field `frozenReason`; `halt(reason)` takes the cause.
- `statusLabel`: new `halted` value.
- New main-only tool `resume_agents`.
- No new commands; `/unhalt` semantics extended (re-arm + nudge).

## Testing

Pure, SDK-free units (extend existing `engine.test.ts` / `spawner.test.ts`):

- Budget crossing: crossing turn returns `abort:false`, sets `frozen` +
  `frozenReason:"budget"`, emits one `halt{reason:"budget"}`. Subsequent
  `recordTurnStart` returns `abort:true`.
- `resume()` clears `frozen`/`frozenReason`, resets `turnsUsed`.
- `halted` marking: `halt()` marks streaming agents `halted`, leaves idle agents
  `idle`. `setStreaming(false)` does not clear `halted`; `resume()` does.
- `statusLabel` precedence incl. `halted`.
- `swarmStateLine` unchanged for both causes.
- Resume nudges only `halted` agents, not `idle` ones; clears the flag.

Shell-side (manual / empirical, documented in the plan):

- Budget escalation message reaches `main` exactly once.
- Persistent widget shows the budget header.
- **Dangling-`tool_use` verification:** drive an agent so the freeze blocks a turn
  right after a tool call, `resume_agents()`, confirm the next turn does not produce a
  provider 400. This is the one item that cannot be unit-tested headlessly.

## Risks

- **Dangling `tool_use`:** blocking the next turn uses `abort()`, which can persist a
  partial aborted assistant message. Same risk as pi's interactive Esc-abort, which
  pi handles (stopReason tracking; compaction catches aborted responses). Mitigated
  by reuse of the proven path; confirmed by the empirical verification step. Cannot
  be removed without the unexposed `shouldStopAfterTurn` hook.
- **Budget overshoot** by ≤ (#active agents) turns — intentional, bounded.
- **Main reflexively resuming** every 200 turns defeats the circuit breaker, but the
  forced, logged checkpoint each 200 turns still kills silent infinite drift
  (inversion: the failure mode we prevent is unbounded uncontrolled spend).
