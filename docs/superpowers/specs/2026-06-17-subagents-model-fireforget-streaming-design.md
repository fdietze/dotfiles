# Subagents: model column, non-blocking delivery, streaming panel

Date: 2026-06-17
Component: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/`

Three independent improvements to the subagents pi extension, discovered while
using it:

1. Show each agent's model in the status rosters.
2. Fix `spawn_agent`/`send_message` blocking: the tool stays "in progress" until
   the target agent finishes its whole turn — delivery is not actually
   fire-and-forget.
3. Render subagent transcripts with full streaming parity (live tokens + tool
   calls) in the `/agents` panel.

## Background / investigation

- `sendUserMessage` (pi `agent-session.js`) internally does `await this.prompt(...)`,
  and `prompt()` resolves only when the **whole turn completes**. The background
  `deliver` in `spawner.ts` awaits it, so delivering the initial `message` to an
  idle agent blocks `spawnAgent` → blocks the `spawn_agent` tool's `execute`.
  Same defect for any `send_message` to an idle agent.
- There is **no reusable high-level transcript widget** in pi. The main-chat
  transcript is assembled imperatively inside `InteractiveMode`
  (`dist/modes/interactive/interactive-mode.js`): it owns a pi-tui `Container`
  (`chatContainer`), a `streamingComponent` (an `AssistantMessageComponent` fed
  `event.message` on every `message_update`), and a `pendingTools` map of
  `ToolExecutionComponent`s. Only the **leaf components** are exported and
  reusable (the panel already imports them).
- During a turn, interactive mode renders from the `message_update` event's
  `event.message`, **not** from `session.messages`. The panel currently rebuilds
  from `session.messages` and its `AgentView.subscribe` listener only receives
  `{ type }`, discarding `event.message` — the payload carrying streaming deltas.
- Swapping the actual main view to a live subagent is **not supported**: the
  public API only offers `ctx.switchSession(path)` (command context), which loads
  a session file into a new foreground session object — a static snapshot, not a
  live attach to a running in-memory background session (and would risk
  double-writer corruption). Hence #3 targets the panel, not the main view.

## #1 — Model column in rosters

- `panel-logic.ts`: add `model: string` to `RosterEntry`. `formatRosterRow`
  renders a short id (strip the `provider/` prefix) in a fixed-width column
  between name and context.
- Call sites pass `model: a.model`: the persistent above-editor roster
  (`index.ts`) and the `/agents` panel roster (`panel.ts`).
- `formatSnapshot` / `list_agents` unchanged (already shows full `provider/id`).

## #2 — Non-blocking delivery (true fire-and-forget)

- `spawner.ts` background `deliver`: drop the `await`. Fire
  `session.sendUserMessage(text, { deliverAs: "followUp" })` and attach `.catch`.
- On rejection, emit a new engine event `{ type: "error"; name; reason; ts }`.
  Add `"error"` to the `AgentEvent` union (`engine.ts`) and a formatter line in
  `formatFeedLines` (`feed.ts`) so it shows in `/feed` and the panel activity log.
- `route` returns immediately again; the existing `queued (busy)` /
  `delivered (woken)` status (computed from `isStreaming` before delivery) is
  preserved.
- Main delivery path is unchanged (already non-blocking via the globalThis sink).

## #3 — Streaming parity in the /agents panel

- `engine.ts`: widen `AgentView.subscribe`'s listener type from
  `{ type: string }` to `{ type: string; message?: unknown; assistantMessageEvent?: unknown }`.
  Stays SDK-free (loosely typed).
- `spawner.ts`: the view's `subscribe` already forwards `session.subscribe`;
  events now carry `message`. No await change.
- `panel.ts`: keep the existing line-based scroll model (minimal change) but stop
  relying on `session.messages` for the in-progress turn:
  - Hold `streamingMessage`, updated on `message_start` / `message_update`
    (assistant role), cleared on `message_end`.
  - `transcriptLines`: render finalized `session.messages`, then append an
    `AssistantMessageComponent` for `streamingMessage` (plus its streaming
    `toolCall`s via `ToolExecutionComponent`) when present.
  - **Dedupe**: if `agent.state.messages` already contains the live message, drop
    the trailing in-progress assistant message before appending, to avoid
    double-render.
- Result: live token streaming + live tool-call rendering in the panel,
  concurrent background agents preserved, no session files, no double-writer risk.

## Out of scope

- Swapping the actual main view to a live subagent (API limitation above).
- Building/extracting a reusable transcript widget (does not exist; we reuse leaf
  components + the ported event glue).

## Testing

- `engine.test.ts`: `error` event emission; covered by `formatFeedLines` case.
- `spawner.test.ts`: `deliver` must not await turn completion — a fake
  `SessionLike` whose `sendUserMessage` returns a never-resolving promise still
  lets `spawnAgent` (with `message`) resolve. A rejecting `sendUserMessage`
  triggers an engine `error` event.
- `panel-logic.test.ts`: `formatRosterRow` with the model column (short id,
  fixed width); dedupe helper if extracted.
- `feed.test.ts`: `error` event formatting.
