/**
 * Context Prune - the agent edits its own context (imperative shell).
 *
 * Idea: in the `context` event every conversation message gets a visible
 * `[#id 1.2k]` marker prepended (id + token size, only for that LLM call,
 * non-destructive). The agent references messages by id and calls `collapse`
 * (fold a range, optionally with a summary), `expand` (restore a fold or a
 * sub-range, which splits it), or `peek` (read a fold's contents without
 * changing state). collapse/expand are the mutators; peek is the read.
 *
 * Why markers in text rather than JSON: the provider serializes only `role` +
 * `content`; extra fields on the message object never reach the model. The
 * entry `id` also lives only on the session *entry* (getBranch()), not on the
 * AgentMessage (see docs/session-format.md). So the context handler correlates
 * entry <-> message via `timestamp`+`role`.
 *
 * Persistence: the cumulative span list is written via pi.appendEntry as a
 * custom entry into the session and reconstructed in session_start/session_tree
 * (analogous to examples/extensions/todo.ts).
 *
 * This file is only the shell: wire pi events/tools. All logic is pure in
 * ./core.ts (tested via ./core.test.ts).
 *
 * Docs: docs/extensions.md ("context" event, registerTool, appendEntry),
 *       docs/session-format.md (entry/message types, getBranch, ids).
 */

import type {
  ExtensionAPI,
  ExtensionContext,
  Theme,
  ThemeColor,
  ToolRenderResultOptions,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import {
  type AgentMessageLike,
  type BranchEntry,
  type BranchMsg,
  type Span,
  PRUNE_ENTRY,
  branchMessages,
  buildOverlay,
  estimateTokens,
  fmtTokens,
  planCollapse,
  planExpand,
  type SearchHit,
  reconstructSpans,
  searchMessages,
  serializeSpan,
  stripLeadingMarkers,
  summarizeTree,
} from "./core.ts";

// --- preview formatting helpers (TUI only) -------------------------------
const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? "" : "s"}`;
// All numeric sizes in this extension are TOKEN estimates (chars/4). The `tok`
// suffix disambiguates them from the `msgs` count on the same preview line.
const tok = (n: number) => `${fmtTokens(n)} tok`;

// Context fill as "20% (202.5k/1000k)", or "" when unknown.
function ctxFill(contextWindow: number, contextTokens: number | null): string {
  return contextWindow > 0 && contextTokens != null
    ? `${Math.round((contextTokens / contextWindow) * 100)}% (${fmtTokens(contextTokens)}/${fmtTokens(contextWindow)})`
    : "";
}

// Shared, symmetric overview tail (model-facing): totals + budget, identical
// after either mutator so the model always sees the same map + pressure.
function overviewTail(
  spans: Span[],
  msgs: BranchMsg[],
  contextWindow: number,
  contextTokens: number | null,
): string {
  const { totalSpans, hiddenTokens } = summarizeTree(spans, msgs);
  const fill = ctxFill(contextWindow, contextTokens);
  return `folds: ${totalSpans} · ${tok(hiddenTokens)} hidden${fill ? ` · ctx ${fill}` : ""}`;
}

// freed/restored magnitude as a % of the context window, with an explicit sign
// (collapse frees -> "−", expand restores -> "+").
function pctOf(tokens: number, contextWindow: number, sign: "−" | "+"): string {
  if (contextWindow <= 0) return "";
  return ` (${sign}${((tokens / contextWindow) * 100).toFixed(1)}%)`;
}

// Shared TUI detail for the two inverse mutators (collapse/expand).
interface PruneDetails {
  action: "collapse" | "expand";
  ok: boolean; // applied something
  msgs: number; // messages collapsed / restored
  deltaTokens: number; // freed (collapse) / restored (expand)
  tail: string; // standing state line (folds · hidden · ctx)
  summaries: string[]; // collapse digests (empty for expand)
  failed: string[]; // unresolved ids
  failLabel: string; // "unknown" | "not folded"
}

// One renderer for both mutators: terse action line when collapsed; standing
// state + digests/failures when expanded. Symmetric glyphs ⊟ (fold) / ⊞ (unfold).
function renderMutate(
  d: PruneDetails,
  opts: ToolRenderResultOptions,
  theme: Theme,
): Text {
  const fold = d.action === "collapse";
  const glyph = fold ? "⊟" : "⊞";
  const past = fold ? "collapsed" : "expanded";
  const verb = fold ? "freed" : "restored";
  const color: ThemeColor = d.ok ? "success" : "warning";
  const head = d.ok
    ? `${glyph} ${past} ${plural(d.msgs, "msg")} · ${verb} ${tok(d.deltaTokens)}`
    : `${glyph} nothing ${past} · ${d.failed.length} ${d.failLabel}`;
  if (!opts.expanded) return new Text(theme.fg(color, head), 0, 0);
  const lines = [theme.fg(color, head)];
  if (d.ok) {
    lines.push(theme.fg("dim", d.tail));
    for (const s of d.summaries) lines.push(theme.fg("dim", `→ ${s}`));
  }
  if (d.failed.length)
    lines.push(theme.fg("warning", `${d.failLabel}: ${d.failed.join(", ")}`));
  return new Text(lines.join("\n"), 0, 0);
}

// TUI detail for peek (read): the tree, a single fold's members, or a miss.
type PeekDetails =
  | { kind: "tree"; folds: number; hidden: number; ctx: string; lines: string[] }
  | { kind: "span"; members: number; tokens: number; rows: string[] }
  | { kind: "miss" };

// TUI detail for search (read).
interface SearchDetails {
  query: string;
  total: number;
  folded: number; // matches that are inside a fold (among shown)
  hits: SearchHit[];
}

export default function (pi: ExtensionAPI) {
  // In-memory source of truth, reconstructed from the session.
  let spans: Span[] = [];

  const branch = (ctx: ExtensionContext) =>
    ctx.sessionManager.getBranch() as unknown as BranchEntry[];
  const reconstruct = (ctx: ExtensionContext) => {
    spans = reconstructSpans(branch(ctx));
  };
  const persist = () => pi.appendEntry(PRUNE_ENTRY, { spans });

  pi.on("session_start", async (_event, ctx) => reconstruct(ctx));
  pi.on("session_tree", async (_event, ctx) => reconstruct(ctx));

  // Strip imitated leading markers from the finalized assistant message before
  // it is stored/displayed (see core: why the prompt alone is not enough). This
  // is the actual fix against imitation + accumulation.
  pi.on("message_end", async (event) => {
    if (event.message.role !== "assistant") return;
    const original = event.message as AgentMessageLike;
    const m = stripLeadingMarkers(original);
    if (m === original) return;
    return { message: m };
  });

  // Inject markers, or replace forgotten ranges with a stub.
  pi.on("context", async (event, ctx) => {
    const messages = buildOverlay(
      event.messages as AgentMessageLike[],
      branch(ctx),
      spans,
    );
    return { messages };
  });

  // --- collapse ------------------------------------------------------------

  const CollapseParam = Type.Object({
    items: Type.Array(
      Type.Object({
        from: Type.String({
          description:
            "Start id (the 8-char hex in a [#id 1.2k] marker). For a single message, omit `to`.",
        }),
        to: Type.Optional(
          Type.String({
            description:
              "End id (inclusive). Defaults to `from`. Order relative to `from` doesn't matter.",
          }),
        ),
        summary: Type.Optional(
          Type.String({
            description:
              "Optional digest shown in place of the range — write it so you can resume from it alone, and hint what detail is inside so you can judge whether to `expand` it later. Omit to hide the range behind a bare stub (still recoverable via search/peek/expand; use for pure noise).",
          }),
        ),
      }),
      {
        description:
          "Ranges to collapse, each { from, to?, summary? }. Multiple items = batch in one call.",
      },
    ),
  });

  pi.registerTool({
    name: "collapse",
    label: "Collapse",
    description:
      "Collapse earlier messages into a stub to keep the model context lean — reversible fold, not delete (content " +
      "stays recoverable via search/peek/expand). Pass a list of ranges by their [#id 1.2k] markers; each is " +
      "{ from, to?, summary? }. With `summary`, the range folds into your digest (finished sub-threads worth " +
      "condensing); without `summary` it is hidden behind a bare stub (pure noise: tool outputs, detours, resolved " +
      "debugging). `to` defaults to `from` for a single message; order of from/to does not matter. Ranges snap " +
      "outward to keep tool call/result pairs whole, and a range overlapping existing folds merges with them " +
      "(joining their summaries) into one fold.",
    promptSnippet:
      "Collapse/fold earlier messages via their [#id N] markers to free context (expand/peek to recover)",
    promptGuidelines: [
      "`[#id 1.2k]` markers are labels the system prepends to each message: the 8-char hex id plus that message's token size. They are NOT part of the message text. Never write a marker in your own replies. Use the id only as an argument to `collapse` / `expand` / `peek` / `search`; use the size to find the fat messages worth collapsing.",
      "Routinely collapse finished sub-threads: pass a range with a short `summary` to condense it, or without `summary` to drop pure noise (tool outputs, detours, resolved debugging). Keeps the working context lean; reversible via `expand`.",
      "To recover something collapsed: `search <keyword>` to locate it across all folds, then `peek` the fold to read it (transient, itself collapsible) without un-folding anything. Only `expand` (optionally a sub-range, which splits the fold) when you need that content live again. Never do the expand-whole-then-recollapse dance.",
      "Write a `summary` you could resume from alone (without `expand`). Lead with open loops (unfinished work, pending decisions/commits/confirmations); then current state (what is now true — commit hashes, paths, passing tests); then decisions and why, including rejected options; then gotchas learned; and hint what detail sits inside the range so you can judge whether to `expand`/`peek` it later. Be specific — name files, symbols, hashes; avoid vague verbs like 'fixed it'. Drop play-by-play and tool output. As terse as possible while still resumable.",
    ],
    parameters: CollapseParam,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const msgs = branchMessages(branch(ctx));
      const plan = planCollapse(msgs, spans, params.items);
      spans = plan.spans;
      if (plan.collapsed) persist();
      const usage = ctx.getContextUsage();
      const win = usage?.contextWindow ?? 0;
      const tail = overviewTail(spans, msgs, win, usage?.tokens ?? null);
      const head = plan.applied.length
        ? `+ collapsed ${plural(plan.collapsed, "msg")} into ${plural(plan.applied.length, "fold")}: ${plan.applied.join(", ")}, freed ${fmtTokens(plan.freedTokens)}${pctOf(plan.freedTokens, win, "−")}` +
          (plan.unknown.length
            ? `. unknown id(s): ${plan.unknown.join(", ")}`
            : "")
        : `Collapsed nothing. unknown id(s): ${plan.unknown.join(", ")}`;
      return {
        content: [{ type: "text", text: `${head}\n${tail}` }],
        details: {
          action: "collapse",
          ok: plan.applied.length > 0,
          msgs: plan.collapsed,
          deltaTokens: plan.freedTokens,
          tail,
          summaries: plan.summaries.filter((s) => s),
          failed: plan.unknown,
          failLabel: "unknown",
        } as PruneDetails,
      };
    },
    renderResult(result, opts, theme) {
      const d = result.details as PruneDetails | undefined;
      return d ? renderMutate(d, opts, theme) : new Text("", 0, 0);
    },
  });

  // --- expand --------------------------------------------------------------

  const ExpandParam = Type.Object({
    items: Type.Array(
      Type.Object({
        from: Type.String({
          description:
            "A fold's stub [#id], or any inner member id (from search/peek). Omit `to` to expand the whole fold that contains this id.",
        }),
        to: Type.Optional(
          Type.String({
            description:
              "End inner id (inclusive). Giving `to` expands the from..to SUB-RANGE and SPLITS the fold: only that range comes back live, the two remnants stay folded (inheriting the summary). For a single found message, set `to` = `from`. Omit `to` to expand the whole fold instead.",
          }),
        ),
      }),
      {
        description:
          "Ranges to expand, each { from, to? }. Multiple items = batch in one call.",
      },
    ),
  });

  pi.registerTool({
    name: "expand",
    label: "Expand",
    description:
      "Restore collapsed messages back into the model context — inverse of collapse. Rule: omit `to` to expand the " +
      "WHOLE fold containing `from`; give `to` to expand only the from..to SUB-RANGE, which SPLITS the fold (the " +
      "rest stays collapsed, remnants inherit the summary) so context never explodes. For surgical recovery, " +
      "`search` or `peek` to get the inner id, then expand from=to=that id. The sub-range snaps to whole tool " +
      "units, so it may bring back a few neighbouring messages to keep a call/result pair intact. If you only " +
      "need to read a value, prefer `peek` and don't expand at all.",
    parameters: ExpandParam,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const msgs = branchMessages(branch(ctx));
      const plan = planExpand(msgs, spans, params.items);
      spans = plan.spans;
      if (plan.applied.length) persist();
      const usage = ctx.getContextUsage();
      const win = usage?.contextWindow ?? 0;
      const tail = overviewTail(spans, msgs, win, usage?.tokens ?? null);
      const head =
        (plan.applied.length
          ? `− expanded ${plural(plan.restoredMsgs, "msg")}: ${plan.applied.join(", ")}, +${fmtTokens(plan.restoredTokens)}${pctOf(plan.restoredTokens, win, "+")}`
          : "Expanded nothing") +
        (plan.noop.length ? `. not folded: ${plan.noop.join(", ")}` : "");
      return {
        content: [{ type: "text", text: `${head}\n${tail}` }],
        details: {
          action: "expand",
          ok: plan.applied.length > 0,
          msgs: plan.restoredMsgs,
          deltaTokens: plan.restoredTokens,
          tail,
          summaries: [],
          failed: plan.noop,
          failLabel: "not folded",
        } as PruneDetails,
      };
    },
    renderResult(result, opts, theme) {
      const d = result.details as PruneDetails | undefined;
      return d ? renderMutate(d, opts, theme) : new Text("", 0, 0);
    },
  });

  // --- peek (read-only) ----------------------------------------------------

  const PeekParam = Type.Object({
    id: Type.Optional(
      Type.String({
        description:
          "A fold's stub [#id], or any inner member id, to print that whole fold's members (each capped ~2000 chars). Omit to list the whole fold tree (overview + budget).",
      }),
    ),
  });

  pi.registerTool({
    name: "peek",
    label: "Peek",
    description:
      "Look at the collapsed-fold structure WITHOUT changing it (read-only). No arg — lists every fold (id, msg " +
      "count, size, summary) plus totals and context budget. With `id` (a fold's stub id or any member id) — " +
      "prints that whole fold's hidden members (inner ids + content, each capped ~2000 chars) so you can " +
      "read-extract a value or pick a sub-range to expand. Only works on an id that belongs to a fold. The " +
      "result is itself a normal message you can later collapse away.",
    parameters: PeekParam,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const msgs = branchMessages(branch(ctx));
      if (!params.id) {
        const { totalSpans, hiddenTokens, lines } = summarizeTree(spans, msgs);
        const usage = ctx.getContextUsage();
        const tail = overviewTail(spans, msgs, usage?.contextWindow ?? 0, usage?.tokens ?? null);
        const text = totalSpans
          ? `${tail}\n${lines.join("\n")}`
          : "No folds. Nothing collapsed yet.";
        return {
          content: [{ type: "text", text }],
          details: {
            kind: "tree",
            folds: totalSpans,
            hidden: hiddenTokens,
            ctx: ctxFill(usage?.contextWindow ?? 0, usage?.tokens ?? null),
            lines,
          } satisfies PeekDetails,
        };
      }
      const span = spans.find(
        (s) => s.fromId === params.id || s.memberIds.includes(params.id!),
      );
      if (!span)
        return {
          content: [{ type: "text", text: `No fold for id ${params.id}.` }],
          details: { kind: "miss" } satisfies PeekDetails,
        };
      const body = serializeSpan(span, msgs);
      const byId = new Map(msgs.map((m) => [m.id, m.message] as const));
      let tokens = 0;
      const rows = span.memberIds.map((id) => {
        const mm = byId.get(id);
        const t = mm ? estimateTokens(mm) : 0;
        tokens += t;
        return `[#${id}] ${mm?.role ?? "?"} · ${tok(t)}`;
      });
      return {
        content: [
          {
            type: "text",
            text: `fold [#${span.fromId}] · ${span.memberIds.length} members:\n\n${body}`,
          },
        ],
        details: {
          kind: "span",
          members: span.memberIds.length,
          tokens,
          rows,
        } satisfies PeekDetails,
      };
    },
    renderResult(result, opts, theme) {
      const d = result.details as PeekDetails | undefined;
      if (!d) return new Text("", 0, 0);
      if (d.kind === "miss")
        return new Text(theme.fg("warning", "◈ no fold for that id"), 0, 0);
      if (d.kind === "tree") {
        if (!d.folds) return new Text(theme.fg("muted", "◈ no folds"), 0, 0);
        const head = `◈ ${plural(d.folds, "fold")} · ${tok(d.hidden)} hidden`;
        if (!opts.expanded) return new Text(theme.fg("accent", head), 0, 0);
        const lines = [
          theme.fg("accent", d.ctx ? `${head} · ctx ${d.ctx}` : head),
          ...d.lines.map((l) => theme.fg("dim", l)),
        ];
        return new Text(lines.join("\n"), 0, 0);
      }
      const head = `◈ ${plural(d.members, "member")} · ${tok(d.tokens)}`;
      if (!opts.expanded) return new Text(theme.fg("accent", head), 0, 0);
      const lines = [
        theme.fg("accent", head),
        ...d.rows.map((r) => theme.fg("dim", r)),
      ];
      return new Text(lines.join("\n"), 0, 0);
    },
  });

  // --- search (read-only, find-by-content) ---------------------------------

  const SearchParam = Type.Object({
    query: Type.String({
      description:
        "Case-insensitive substring to find across all messages (live and collapsed).",
    }),
  });

  pi.registerTool({
    name: "search",
    label: "Search",
    description:
      "Find a keyword across the whole conversation — live AND collapsed messages (matches message text, thinking, " +
      "and tool-call arguments). Returns up to the first 20 matches, each with its [#id], role, which fold it is " +
      "hidden in (if any), and a snippet. The efficient way to locate content before peek/expand when there are " +
      "many folds (find-by-content, vs peek's look-by-id).",
    parameters: SearchParam,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const msgs = branchMessages(branch(ctx));
      const { hits, total } = searchMessages(msgs, spans, params.query, 20);
      const text = total
        ? `${total} hit(s) for "${params.query}"${total > hits.length ? ` (showing ${hits.length})` : ""}:\n` +
          hits
            .map(
              (h) =>
                `[#${h.id}] ${h.role}${h.foldFrom ? ` (folded in [#${h.foldFrom}])` : ""} · ${h.snippet}`,
            )
            .join("\n")
        : `No hits for "${params.query}".`;
      return {
        content: [{ type: "text", text }],
        details: {
          query: params.query,
          total,
          folded: hits.filter((h) => h.foldFrom).length,
          hits,
        } satisfies SearchDetails,
      };
    },
    renderResult(result, opts, theme) {
      const d = result.details as SearchDetails | undefined;
      if (!d) return new Text("", 0, 0);
      if (!d.total)
        return new Text(theme.fg("muted", `⌕ no hits for "${d.query}"`), 0, 0);
      const head =
        `⌕ ${plural(d.total, "hit")} for "${d.query}"` +
        (d.folded ? ` · ${d.folded} folded` : "");
      if (!opts.expanded) return new Text(theme.fg("accent", head), 0, 0);
      const rows = d.hits.map((h) =>
        theme.fg(
          "dim",
          `[#${h.id}] ${h.role}${h.foldFrom ? ` (in ${h.foldFrom})` : ""} · ${h.snippet}`,
        ),
      );
      return new Text([theme.fg("accent", head), ...rows].join("\n"), 0, 0);
    },
  });
}
