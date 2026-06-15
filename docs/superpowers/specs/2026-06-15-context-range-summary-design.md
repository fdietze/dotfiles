# Context Range Summary — Design

Date: 2026-06-15
Component: `modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`

## Goal

Extend the existing `context-prune` pi extension so the agent can collapse a
contiguous range of its own conversation into a single, self-written summary
message — not just tombstone individual messages. This reclaims context budget
on long, abandoned sub-threads (e.g. a finished investigation) while keeping
the gist available.

This builds on the existing extension, which already:
- injects a visible `[#id]` marker into every taggable message in the `context`
  event (non-destructive, correlated entry↔message via `timestamp`+`role`),
- offers `forget_messages` / `recall_messages` to tombstone/restore single
  messages, and
- persists the pruned set as a custom session entry (`context-prune`),
  reconstructed in `session_start` / `session_tree`.

## Decisions (from brainstorming)

1. **Summary source:** the agent supplies the summary text as a tool argument.
   No internal LLM call.
2. **Range spec:** two ids, `from` + `to`, inclusive, resolved in branch order
   (order-agnostic; min/max).
3. **Structural realisation:** true collapse — the range is replaced by ONE
   synthetic summary message (not a tombstone-per-message).
4. **Pairing at boundaries:** `toolCall` + `toolResult` (including the parallel
   calls/results of one turn) are an atomic unit. If a boundary splits a unit,
   the range snaps outward until the unit is whole. This guarantees no orphaned
   tool pairs ever leave the context.
5. **Re-summarising a summary:** flat. A new range that overlaps existing spans
   absorbs them (union of underlying originals). `recall` of the new span
   restores ALL original messages at once — no layered peeling.

## Tool

```
forget_range({ from: string, to: string, summary: string })
```

- `from` / `to`: 8-hex ids of currently visible messages. Each may be a real
  entry id OR the id of an existing summary span (which equals that span's
  first-member id). Order between them does not matter.
- `summary`: free text written by the agent.

Validation: both ids must resolve to a visible message (real taggable entry or
an existing span's `fromId`). Unknown ids → error result listing them, no state
change.

`recall_messages` and `forget_messages` keep their current signatures. `recall`
is extended to also dissolve a span when the given id is a span `fromId`.

## State

Extends the persisted custom entry. Source of truth in memory:

- `pruned: Set<id>` — single-message tombstones (unchanged).
- `spans: Array<{ fromId: id, memberIds: id[], summary: string }>`
  - `memberIds`: the REAL entry ids covered, always flattened (never another
    span id), contiguous in branch order, ascending.
  - `fromId`: equals `memberIds[0]`; it is the visible id the synthetic summary
    message carries, so a summary can itself be referenced in a later range.

Persistence payload becomes `{ pruned: id[], spans: [...] }`. `reconstruct`
reads both; the latest `context-prune` custom entry on the branch wins
(cumulative snapshot, as today). Invariants maintained on every mutation:
spans are pairwise disjoint and each covers a contiguous run.

## Range resolution algorithm (forget_range)

1. Build the ordered list of branch message entries (taggable roles only),
   with an index per entry id.
2. Resolve `from` / `to` to real ids: a span id maps to its first member
   (`from`) or last member (`to`); a real id maps to itself. Set
   `lo = min(index)`, `hi = max(index)`.
3. **Tool-unit snapping:** expand `lo` down and `hi` up until no
   `toolCall`/`toolResult` unit straddles a boundary. A unit is an assistant
   message bearing `toolCall` block(s) together with the `toolResult`
   message(s) that answer those call ids (one turn may have several parallel
   calls + results).
4. **Absorption (flat):** any existing span whose `memberIds` intersect
   `[lo..hi]`, and any `pruned` tombstone whose id falls in `[lo..hi]`, are
   removed; `lo`/`hi` are extended to fully cover absorbed spans. Recompute
   `memberIds` as all real entry ids in the final `[lo..hi]`.
5. Create the new span keyed by `fromId = memberIds[0]` with the agent's
   `summary`.

Because the final range always covers whole tool-units, dropping every member
and emitting one summary message can never orphan a tool pair.

## Context rendering (context event handler)

Same entry↔message correlation as today (per `(timestamp, role)` queue). For
each message that resolves to an id:

- id is a span `fromId` → replace this message with ONE synthetic `user`
  message tagged `[#fromId]`, content `(summary) <text>`.
- id is a non-first member of a span → omit the message entirely.
- id ∈ `pruned` → tombstone in place (existing behaviour).
- otherwise → tag with `[#id]` (existing behaviour).

Role of the synthetic message is `user`, matching how compaction-style
summaries are injected; if it lands adjacent to another user message, providers
merge consecutive same-role messages without error.

## Reversibility

- `recall_messages([id])`: if `id` is a span `fromId`, delete that span → all
  its original members reappear and get re-tagged on the next call. If `id` is
  in `pruned`, remove it (existing behaviour). Flat model: one recall restores
  the whole original range at once.

## Edge cases

- `from == to`: a single-member span with a summary; handled by the same path,
  no special case.
- Reversed order (`to` before `from`): handled by min/max in step 2.
- A summary span referenced again in a new range: resolved via its `fromId`
  in step 2, then absorbed in step 4.

## Out of scope (YAGNI)

- Automatic/LLM-generated summaries.
- Non-contiguous id lists for ranges.
- Nested/layered recall of summaries.
- Configurable roles for the synthetic message.

## Testing notes

Hard to unit-test without the pi runtime; verification is manual in a live pi
session after a home-manager switch + `/reload`:
- collapse a range spanning a tool call/result, confirm one summary message and
  no provider error;
- collapse a range whose boundary splits a tool pair, confirm outward snapping;
- re-summarise a range that includes an existing summary, confirm flat union;
- `recall` the summary id, confirm all originals reappear.
