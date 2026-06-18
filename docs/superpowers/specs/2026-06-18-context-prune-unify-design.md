# context-prune: unify to forget/remember

## Problem

The extension exposes three tools with overlapping intent and inconsistent
vocabulary:

- `forget_messages(ids)` — tombstone: hide one message's content, keep a stub.
- `forget_range(from,to,summary)` — collapse a range into one authored summary.
- `recall_messages(ids)` — universal inverse of both.

Two distinct verbs ("forget" twice) for what is really *one* operation with a
parameter, plus two parallel internal mechanisms:

- `pruned: Set<string>` — per-message tombstones.
- `spans: Span[]` — summarized ranges.

"forget"/"prune" also oversell destruction for a non-destructive, reversible
overlay. The double bookkeeping (`total = pruned.size + spans.length`,
`tombstone()` preserving toolCall blocks for pairing) is incidental complexity.

## Design

One operation, optional summary. One symmetric pair of tools.

### Tools

```
forget(items: [{ from: string, to?: string, summary?: string }])
remember(ids: [string])
```

- `to` defaults to `from` (single message/unit).
- `summary` present → range collapses into an in-place stub carrying the digest.
- `summary` absent → range collapses into a `(forgotten N)` stub.
- `items` is a list → multiple ranges/singles forgotten in one call (batching,
  fewer round-trips). Non-contiguous singles = multiple `{from}` items.
- `remember(ids)` dissolves any span by its `fromId`, restoring originals.

### One internal mechanism

Delete `pruned` Set and `tombstone()`. Everything is a **span**:

```
interface Span { fromId: string; memberIds: string[]; summary: string }
```

- A single-member span with empty `summary` *is* the old tombstone.
- Persisted custom entry stores only `{ spans }`.
- `total` = `spans.length`.

### Pairing safety for free

Spans already snap to whole tool-units via `expandRange`/`unitBounds`, so
collapsing any range to one user stub can never orphan a toolCall/result pair.
That is the only reason `tombstone()` had to keep toolCall blocks — so that
logic is removed, not reimplemented.

### Stub rendering (context overlay)

For each span: drop hidden members, replace `fromId` position with one synthetic
`user` message:

- summary present: `[#id] (summary) <text>`
- summary absent: `[#id] (forgotten N messages)`

### Tool-call preview (renderResult)

Show the digest in the preview so the user sees *what* was compacted:
`✓ forgot N → "<summary>"` (or `✓ forgot N messages` when no summary).
Free: `renderResult` is TUI-only, never serialized into context, and the
summary already lives in context via the tool-call args.

### Out of scope (YAGNI)

- **Summary dedup.** The digest sits in both the tool-call args and the injected
  stub (~tens of tokens). Removing it needs a span→callId backref + editing
  toolCall-input JSON in the overlay, and risks confusing the model. Not worth
  it. Keep the in-place stub canonical; leave call args untouched.

## Naming changes

| Old | New |
|---|---|
| `forget_messages`, `forget_range` | `forget` (one tool) |
| `recall_messages` | `remember` |
| `pruned` Set, `tombstone()` | removed (subsumed by spans) |
| `PRUNE_ENTRY = "context-prune"` | keep (persistence key; back-compat) |

`Span` kept (it now means "any forgotten range"). Imitation-marker strip from the
prior fix is unchanged.

## Migration

Old sessions persisted `{ pruned, spans }`. `reconstruct()` should still read
legacy `pruned` ids and convert each to a single-member span with empty summary,
so reload of old sessions keeps prior forgets. New persists `{ spans }` only.
