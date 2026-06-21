# context-prune: token-aware markers + collapse/expand/peek

## Goal
Let the model manage its own context efficiently near the budget ceiling. Today
at ~80% fill it can't tell *what* to drop or *how much* anything costs, and
recovering one item from a forgotten range forces a remember-whole → explode →
re-collapse dance.

## Mental model
The extension's tools model a datastructure: an immutable linear message base +
a flat **span overlay** (collapsed ranges, each a tool-unit-snapped id-range with
an optional summary, rendered as one stub). This is exactly **code folding**. The
minimal closed op-algebra over a fold structure is three ops, one per effect
class (SoC):

| effect | tool | note |
|---|---|---|
| collapse range → stub | **collapse** (was `forget`) | only token-freeing move |
| expand stub/sub-range → live | **expand** (was `remember`) | only permanent-restore move; range-aware (splits spans) |
| read without mutating | **peek** (new) | overview tree + drill-in |

Hierarchy is a *view* (peek), not stored — store stays flat. Map ≠ territory.

## Decisions
- **Per-message size markers**: `[#a2aadc00 1.2k]` on every live taggable msg.
  Number inside brackets; `LEADING_FAKE_MARKERS` widened to still strip model
  imitation.
- **fmtTokens**: `<1000 → "340"`, else `"3.4k"` / `"12k"`. One formatter (DRY),
  reused in markers, stubs, tails, peek.
- **estimateTokens**: pure chars/4 mirroring pi's heuristic (text + thinking +
  toolCall name/args). Kept in core (no pi import) for testability.
- **Stubs show hidden cost**: `(forgotten 5 messages, 3.4k hidden)` /
  `(summary, 3.4k hidden) <summary>`.
- **Mutator tails (symmetric, lean)**: collapse/expand return an opposite-signed
  delta + one-line totals + budget:
  - `+ collapsed [#id]: 5 msgs, freed 3.4k (−1.7%) · folded: 3 spans, 12k, ctx 78%`
  - `− expanded [#id]: 5 msgs, +3.4k (+1.7%) · folded: 2 spans, 8.6k, ctx 80%`
  Both in TUI (renderResult) and model-facing text. ctx% from
  `ctx.getContextUsage()` (shell-side I/O); freed/restored computed in core from
  member tokens (getContextUsage().tokens lags after the overlay change, so it is
  not used for the delta).
- **peek** (read, transient toolResult — itself taggable/forgettable):
  - `peek()` → tree: every span `[#id] · N msgs · Xk · summary`, totals, ctx%.
  - `peek(id)` → serialize span members: per msg `[#innerid] role Xk` + content
    capped ~2000 chars. Reveals inner ids for surgical expand; lets the agent
    read-extract a value without un-collapsing anything.
- **expand is range-aware (kills the dance)**: `expand(from, to?)` symmetric with
  collapse. A sub-range of a span **splits** it: restore subset live, leave the
  two remnants folded, **both inheriting the original summary** (lossless). Bare
  span fromId (no `to`) → expand whole span. Snap to tool units, clamp within the
  span (remnants stay whole-unit).
- **Naming**: collapse/expand precise + reversible-signalling (vs "forget" which
  wrongly implies permanence); matches the fold model. peek = fold-preview.

## Deferred (YAGNI)
- Nested-tree storage (peek gives the tree *view*; flat store suffices).
- Global fill line injected every turn (tails + peek already surface budget).
- Reduced marker density / turn-anchor addressing (revisit if marker overhead
  bites).

## core.ts (pure) — changes
- `estimateTokens(msg)`, `fmtTokens(n)` (new).
- `tag(msg, id, tokens)` → `[#id <fmt>]`; widen `LEADING_FAKE_MARKERS`.
- `buildOverlay`: precompute id→tokens once; tag live msgs with size; stubs show
  hidden cost.
- `planCollapse` (rename `planForget`) → add `freedTokens`.
- `planExpand` (rename `planRemember`) → range-aware `{from,to?}[]`, span split,
  remnants inherit summary; returns `restoredTokens`.
- `summarizeTree(spans, msgs)` → totals + per-span lines (peek() + mutator tails).
- `serializeSpan(span, msgs, cap=2000)` → peek(id) body.

## index.ts (shell) — changes
- Rename tools `forget`→`collapse`, `remember`→`expand`; register `peek`.
- `expand` params become range items `{from, to?}` (symmetric with collapse).
- Compose tails with `summarizeTree` + `ctx.getContextUsage()`.
- Update prompt guidelines: marker `[#id Nk]` format; collapse/expand/peek roles;
  "peek to read-extract (transient); expand a sub-range to pull a subset live
  without exploding context."

## Tests (core.test.ts)
estimateTokens; fmtTokens boundaries (999/1000/12000); widened-regex strip of
`[#id 1.2k]`; marker format in buildOverlay; stub hidden-cost; planCollapse
freedTokens (incl. collapse-over-existing-span net); planExpand whole-restore,
sub-range split into two remnants inheriting summary, restoredTokens;
summarizeTree; serializeSpan truncation.
