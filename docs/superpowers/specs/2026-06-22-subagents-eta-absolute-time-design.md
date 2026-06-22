# Subagents: absolute-time ETA in agent status

## Problem

Subagents express ETA in their status line as a *relative* duration (`ETA 20min`),
which goes stale the moment it's read — at 15:00 "ETA 20min" means 15:20, but read
at 15:15 it still says "20min". The `set_status` tool description already *asks* for
an absolute clock ETA, but the agent cannot reliably comply: an LLM agent does not
know the wall-clock time, so it falls back to the duration it actually knows.

Prompt instruction alone cannot fix this. The extension must own the clock.

## Approach

Split responsibility along what each party actually knows:

- **Agent knows the duration** ("tests take ~20min") → supplies `etaMinutes`.
- **Extension knows the clock** → converts duration to an absolute target timestamp
  at write time and renders absolute clock time, recomputing the relative hint live.

Display target: `running tests · ETA ~15:20 (in 45min)`.

The absolute anchor (`~15:20`) is the source of truth and never goes stale. The
relative hint `(in 45min)` is recomputed at each render for at-a-glance freshness;
it may lag slightly because the panel re-renders on events, not on a periodic tick
(acceptable — KISS; absolute time is always correct).

## Decisions

- **Two-arg `set_status`**: `status` (phrase, no ETA embedded) + optional
  `etaMinutes: number`. Separates the agent's clean duration channel from the
  extension-owned clock/formatting. Rejected: freeform duration string parsing
  (`"1h30m"`) — more failure surface, violates KISS; regex-rewriting the freeform
  status — brittle, fights the agent.
- **Unit = minutes** (`etaMinutes`). Matches how agents reason about task duration;
  subagent ETAs are coarse. Rejected seconds (overkill).
- **Omit clears**: calling `set_status` without `etaMinutes` clears any prior ETA.
  Each call fully specifies the visible status — no hidden carryover, no stale ETA
  surviving across phases. Matches the tool's existing "describe CURRENT state" framing.
- **Overdue rendering**: `ETA ~15:20 (overdue)` — keep the absolute anchor, flag late,
  no number. Knowing it's late matters; exact overrun rarely does (an agent that cares
  re-sets a fresh ETA). Rejected: quantified `(overdue 7min)`, dropping ETA on pass
  (hides overrun — bad for the "when are you free" use case).
- **Store absolute timestamp, not text**: `etaTs` (epoch ms) so display always renders
  true clock time and can recompute the relative hint.
- **Ephemeral**: `etaTs` not persisted. `customStatus` is already not persisted (status
  is re-derived from the transcript tail on restart); a restored ETA would be stale
  anyway. Consistent.

## Implementation

### Data — `engine.ts`
- Add `etaTs?: number` to `AgentRecord` (absolute target epoch ms).
- Extend `setCustomStatus(name, status, etaTs?)` to set both atomically;
  `etaTs === undefined` clears it.

### Tool API — `index.ts` `set_status`
- Add optional parameter `etaMinutes: number`.
- Execute:
  ```
  const etaTs = args.etaMinutes != null ? Date.now() + args.etaMinutes * 60000 : undefined;
  engine.setCustomStatus(selfName, args.status, etaTs);
  ```
- Description change: drop the "include an ABSOLUTE ETA in the text (e.g. ETA 14:32)"
  paragraph. Replace with: express ETA via `etaMinutes` (a duration from now); the
  extension renders the absolute clock time. Keep the "describe CURRENT state / set a
  resting state before idle" guidance.
- Bump version comment → v7 (current head is v6: setCustomStatus).

### Formatter — new `eta.ts` (functional core, pure)
```
formatEtaSuffix(etaTs: number, now: number): string
```
- future: `ETA ~15:20 (in 45min)`
- overdue (`now > etaTs`): `ETA ~15:20 (overdue)`
- clock format `~HH:MM`, 24-hour, zero-padded.
- relative `(in Xmin)`; `(in Xh Ym)` when remaining ≥ 60 min.

Single purpose, imported by both render surfaces.

### Render wiring
- **panel-logic.ts**: add `etaTs?` to `RosterEntry`. Build the custom-status display as
  `customStatus + (etaTs ? " · " + formatEtaSuffix(etaTs, now) : "")`, then place per
  existing order: `customDisplay · system`. Pass `now = Date.now()` from the render shell.
- **feed.ts `formatSnapshot`**: `AgentRecord` already carries `etaTs`. Build the same
  custom-status display, place per existing order: `system · customDisplay`.
- index.ts: thread `etaTs` into the `RosterEntry` it constructs (alongside `customStatus`)
  and pass `now`.

## Tests
- **eta.test.ts** (new): future, overdue, hours rollover (`in 1h 5min`), midnight /
  zero-padding (`~09:05`, `~00:30`), exact-boundary (now == etaTs).
- **panel-logic.test.ts**: ETA suffix present when `etaTs` set; absent when omitted;
  correct order relative to system status.
- **feed.test.ts**: same for snapshot order.

## Files touched
- `engine.ts` — `AgentRecord.etaTs`, `setCustomStatus` signature
- `index.ts` — `set_status` param + execute + description + version bump + RosterEntry wiring
- `eta.ts` (new) — `formatEtaSuffix`
- `eta.test.ts` (new)
- `panel-logic.ts` — `RosterEntry.etaTs`, display assembly
- `feed.ts` — snapshot display assembly
- `panel-logic.test.ts`, `feed.test.ts` — extended
