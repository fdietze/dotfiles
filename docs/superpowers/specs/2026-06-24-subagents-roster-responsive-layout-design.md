# Subagents roster: responsive single-line table layout

## Problem

The persistent agents roster (widget above the editor + `/agents` panel) renders each
agent on one line. Current layout puts an **unbounded** agent-set free-text status
*mid-row, before* the structured columns, then clips the whole line to terminal width.
Consequences seen live:

- **Name collisions:** the 18-char name column truncates the *tail*, so two agents with a
  shared prefix (`risk-R-UniformApp…`) render identically — indistinguishable.
- **Structure loss:** a long custom status pushes the structured columns
  (model/context/targets) off the right edge; the *running* agent loses its context%.
- **No alignment:** status width varies per row, so model/context start at different x.
- Disliked glyphs: inter-column `·`, the `→` targets arrow.

## Goal

A responsive, **aligned**, single-line table that degrades gracefully on narrow terminals,
keeps the scannable signals, and bounds the free-text status.

## Columns (display order, left → right)

| # | column | protected | width rule |
|---|--------|-----------|-----------|
| 1 | name | yes | max name width across agents, cap **24**; **middle-ellipsis** beyond (keeps distinguishing tail) |
| 2 | custom status | collapsible (4th) | hard max **32**, tail ellipsis |
| 3 | system status | yes | max across agents, cap **18**; tone-styled (idle/busy/error) |
| 4 | eta | yes | `ETA ~HH:MM` (10); blank if unset for that agent; **whole column vanishes** if no agent has one |
| 5 | context | collapsible (3rd) | fixed `  178k/1000k (18%)` (~16) |
| 6 | model | collapsible (1st) | cap **14**, ellipsis |
| 7 | targets | collapsible (2nd) | variable, max-content width |

- **Protected (never hidden):** name, system status, eta.
- **Collapse order when width runs out:** model → targets → context → custom status.

## Layout algorithm (roster-wide, one pass — required for alignment)

`formatRoster(entries, width, opts) → string[]`

1. Compute each column's natural width = max rendered content across all agents, clamped to
   its cap. eta column is skipped entirely if no agent set an eta.
2. Start with the protected columns. Sum widths + 1-space gaps.
3. Add collapsible columns in **keep priority** (custom status, context, targets, model),
   each only if it still fits `width`. A column is included for ALL rows or none — this is
   what keeps columns aligned.
4. Render every row using the surviving columns at the shared widths: pad to width, truncate
   over-long content with a tail ellipsis (`…`); middle-ellipsis only for name.
5. Final guard: `truncateToWidth(line, width)` clips trailing overflow (wide glyphs/rounding).

Columns are separated by a single space — **no inter-column `·`**.

## Targets format

`formatSendTargets` output changes:
- `➜main[3]` — arrow (U+279C, single-width) + target + `[count]` in brackets.
- single message → `➜main` (no count).
- multiple targets space-joined: `➜main[3] ➜coder`.

## Custom status bound

- Render caps the custom status at 32 chars (tail ellipsis).
- The `set_status` tool description states the limit: "keep your status ≤ 32 chars; longer is
  truncated in the roster." So the agent writes within the budget instead of being silently cut.

## Symbols

- Inter-column `·` removed (alignment replaces it). `·` survives only inside compound tokens
  (none remain after targets switch to `[n]`).
- `→` targets arrow → `➜`.
- **Kept as-is:** `▸` selection cursor (`/agents` panel only), and the swarm state line
  `▶ live` / `⏸ halted`.

## Scope / call sites

- New pure function `formatRoster` in `panel-logic.ts`; replaces the per-row
  `.map(formatRosterRow)` in `index.ts` (`updateStatus`) and `panel.ts`. `formatRoster` takes
  `opts.selectedIndex?` (panel cursor + selected styling) and `opts.styleStatus` (tone styler);
  widget passes no selection.
- `formatRosterRow` (per-row) is removed or reduced to an internal helper.
- `formatSnapshot` (feed.ts, the LLM-facing text roster) is **out of scope** — different
  consumer; keep its current format aside from the shared `formatSendTargets`/ETA helpers.

## Testing

Pure function, fully testable (no TUI/clock dependency):
- alignment: equal-width columns across rows.
- name middle-ellipsis preserves head + tail; two shared-prefix names stay distinct.
- collapse order: shrinking width drops model, then targets, then context, then custom status.
- protected columns survive narrowest width.
- eta column vanishes when no agent has an eta; present (padded blank) when some do.
- targets `[count]` shown for >1, omitted for 1.
- custom status capped at 32 with ellipsis.
