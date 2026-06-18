# Subagents history persistence + restart resume

Date: 2026-06-18
Extension: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/`
Builds on: `2026-06-18-subagents-turn-budget-escalation-design.md` (halt/resume).

## Problem

Background agents use `SessionManager.inMemory(cwd)` — zero disk persistence. Their
histories live only in the `globalThis` Engine singleton: they survive `/reload`
(same process) but die on a pi restart or crash. The `main` agent, by contrast, is
a normally persisted session.

Goal: persist subagent histories durably so a restart/crash can be resumed, reusing
the existing halt/resume mechanism for reactivation.

## Core idea

A restart ≈ a halt that also wiped RAM. So:

1. Always write subagent transcripts to disk (per-message, automatic).
2. Keep a small membership index (`roster.json`) per main session.
3. On cold start, rebuild the swarm **as halted** (`frozen=true`), each agent's
   status derived from its transcript tail.
4. Reactivate with the existing `resume_agents()` / `/unhalt` — nudges the `halted`
   agents, leaves `idle` ones alone. **No new reactivation code.**

## Verified SDK facts

- `createAgentSession` rehydrates: `sessionManager.buildSessionContext()` →
  `agent.state.messages = existingSession.messages` (also restores model). So
  `SessionManager.open(file)` + `createAgentSession({sessionManager})` resumes the
  full transcript.
- Per-message persistence is automatic for a persisted `SessionManager` (the session
  subscribes its own writer; each message_end appends to the JSONL).
- `SessionManager.create(cwd, sessionDir, opts)`, `.open(path)`, `.appendMessage(msg)`
  (persists), `.getSessionFile()`, `.getSessionId()` all exist.
- `ctx.sessionManager.getSessionId()` gives the **main** session id (keys the dir).
- `session_start` event carries `reason: "startup"|"reload"|"new"|"resume"|"fork"`.
- **pi does NOT reconcile dangling `tool_use` on load** (`convertToLlm` and
  `buildSessionContext` pass messages verbatim). A crash mid-tool can leave a
  trailing assistant `tool_use` with no `tool_result` → provider 400 on resume. We
  must reconcile at restore.

## Layout

```
sessions/<encoded-cwd>/subagents/<mainSessionId>/
    roster.json                # membership index (overwritten on spawn/kill)
    <generated-id>.jsonl       # one per agent (pi-format; name->file via roster.json)
```

Nested under the per-cwd dir so pi's pickers never list them (`list(cwd)` reads
`<encoded-cwd>/*.jsonl` non-recursively; `listAll()` scans `sessions/*/` one level).
Each agent session's display name is set to the agent name (NewSessionOptions) for
readability when browsed directly.

`roster.json` is JSON → exempt from the runtime-header-comment rule.

## roster.json shape

```json
[ { "name": "...", "spawnedBy": "...", "depth": 1,
    "model": "provider/id", "systemPrompt": "...", "sessionFile": "/abs/path.jsonl" } ]
```

`systemPrompt` must be stored: it is applied at runtime via `systemPromptOverride`
and is NOT in the transcript, so restore needs it to rebuild the session prompt.
Killed agents are removed from the array (their `.jsonl` stays on disk — browsable).

## Engine changes (`engine.ts`)

- `AgentRecord` gains `systemPrompt?: string` and `sessionFile?: string`.
- `attach()` opts gain `systemPrompt?` and `sessionFile?` (set by the spawner).
- New `addAgent` is reused for restore (already public). No policy changes.

## Spawner / createSession changes

- `SpawnerDeps.createSession` returns `{ session: SessionLike; sessionFile?: string }`
  (was `SessionLike`). The spawner passes `sessionFile` + `spec.systemPrompt` into
  `engine.attach`.
- index.ts `createSession(spec, existingFile?)`:
  - new: `SessionManager.create(cwd, subDir, { name: spec.name })`
  - restore: `SessionManager.open(existingFile)` (after reconciliation)
  - returns the session + `sm.getSessionFile()`.

## Restore (`index.ts`, in `session_start`)

Trigger: background agents absent (`engine.list()` is just `main`) AND a `roster.json`
exists for the current `getSessionId()` AND not already restored for this id (a
`globalThis` guard set). This naturally:
- runs on a true cold start / `pi --resume`,
- skips `/reload` (singleton still holds the agents),
- restores exactly the resumed conversation's swarm (empty for a new session).

Per roster entry:
1. `sm = SessionManager.open(sessionFile)`.
2. **Reconcile** dangling `tool_use` (pure helper): find the last assistant message's
   tool-call ids with no following matching `toolResult`; for each, `sm.appendMessage`
   a synthetic `toolResult` (`isError:true`, "Interrupted — not completed"). This also
   permanently repairs the file.
3. `createSession(spec, sessionFile)` → rehydrated session.
4. `engine.addAgent({... halted: deriveStatus(messages) === "halted", ...})`, with the
   swarm set `frozen` (call `engine.halt("manual")` once after restoring, or set a
   restored flag). Restored-but-idle agents stay `idle` (no nudge on resume).

Set the swarm frozen so the roster shows `⏸ halted` and one `resume_agents()` /
`/unhalt` reactivates exactly the `halted` agents.

## Pure helpers (`persistence-logic.ts`, fully tested, no SDK)

- `danglingToolResultIds(messages): {id, name}[]` — last assistant's tool-call ids
  lacking a following `toolResult`.
- `deriveStatus(messages): "idle" | "halted"` — `halted` if the transcript ends
  mid-turn (trailing assistant with pending/unmatched tool calls, or stopReason
  aborted/error), else `idle`.
- `serializeRoster(agents)` / `parseRoster(json)` — shape guard.

Shell I/O (`persistence.ts`): `subagentsDir(...)`, `writeRoster`, `readRoster`. Kept
thin; logic lives in `persistence-logic.ts`.

## Roster write triggers

On `spawn` (after attach sets sessionFile) and `kill` engine events, overwrite
`roster.json` from `engine.list()` (background agents only, skipping `pending`/
`spawning` ones without a sessionFile yet). Not per turn — transcripts self-persist.

## Out of scope (YAGNI)

- Swapping swarms when switching sessions at runtime (`/resume` mid-session). v1
  restores on cold start only; a runtime switch keeps the current swarm.
- Auto-resume without the halted checkpoint (decided: restore-as-halted).
- GC of old subagent files (kept forever, like pi sessions; manual cleanup).

## Testing

Pure units (`persistence-logic.test.ts`):
- `danglingToolResultIds`: trailing assistant with 1 / N tool calls, none / some
  matched; clean transcript → empty; no trailing assistant → empty.
- `deriveStatus`: clean end → idle; trailing tool_use → halted; aborted/error → halted.
- roster round-trip serialize/parse; ignores malformed.

Engine units (extend existing): `attach` stores `systemPrompt`/`sessionFile`;
`addAgent` with `halted:true` reflected by `statusLabel`.

Manual / empirical:
- Spawn agents, kill one, restart pi (`--resume`): roster restores remaining agents
  as halted/idle; `resume_agents()` re-nudges the halted ones; killed agent absent but
  its `.jsonl` present.
- **Crash-resume:** SIGKILL pi while an agent runs a tool, restart, restore →
  reconciliation appends the synthetic `toolResult`, resume produces no provider 400.

## Risks

- **Crash dangling `tool_use`:** handled by restore-time reconciliation (pi does not
  do it — verified). Covered by the empirical crash test.
- **Stale roster on hard crash:** `roster.json` is written on spawn/kill only, so a
  crash cannot leave it more stale than the last membership change; transcripts are
  the source of truth for status. An agent in the roster whose `.jsonl` is missing is
  skipped on restore.
- **Concurrent main sessions** sharing a cwd are isolated by `mainSessionId` in the
  path — no collision.
