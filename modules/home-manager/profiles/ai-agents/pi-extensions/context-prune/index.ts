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
  fmtTokens,
  planCollapse,
  planExpand,
  reconstructSpans,
  searchMessages,
  serializeSpan,
  stripLeadingMarkers,
  summarizeTree,
} from "./core.ts";

interface PruneDetails {
  action: "collapse" | "expand";
  applied: string[];
  unknown: string[];
  noop: string[];
  collapsed: number;
  summaries: string[];
  total: number;
  deltaTokens: number; // freed (collapse) or restored (expand)
  tail: string; // the shared overview tail line(s)
}

// Shared, symmetric overview tail: totals + budget, identical after either
// mutator so the model always sees the same map + pressure. ctx% is the only
// I/O (getContextUsage) - everything else is pure core.
function overviewTail(
  spans: Span[],
  msgs: BranchMsg[],
  contextWindow: number,
  contextTokens: number | null,
): string {
  const { totalSpans, hiddenTokens } = summarizeTree(spans, msgs);
  const ctx =
    contextWindow > 0 && contextTokens != null
      ? ` · ctx ${Math.round((contextTokens / contextWindow) * 100)}% (${fmtTokens(contextTokens)}/${fmtTokens(contextWindow)})`
      : "";
  return `folds: ${totalSpans} · ${fmtTokens(hiddenTokens)} hidden${ctx}`;
}

// freed/restored magnitude as a % of the context window, with an explicit sign
// (collapse frees -> "−", expand restores -> "+").
function pctOf(tokens: number, contextWindow: number, sign: "−" | "+"): string {
  if (contextWindow <= 0) return "";
  return ` (${sign}${((tokens / contextWindow) * 100).toFixed(1)}%)`;
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
        ? `+ collapsed ${plan.collapsed} msgs into ${plan.applied.length} fold(s): ${plan.applied.join(", ")}, freed ${fmtTokens(plan.freedTokens)}${pctOf(plan.freedTokens, win, "−")}` +
          (plan.unknown.length
            ? `. unknown id(s): ${plan.unknown.join(", ")}`
            : "")
        : `Collapsed nothing. unknown id(s): ${plan.unknown.join(", ")}`;
      return {
        content: [{ type: "text", text: `${head}\n${tail}` }],
        details: {
          action: "collapse",
          applied: plan.applied,
          unknown: plan.unknown,
          noop: [],
          collapsed: plan.collapsed,
          summaries: plan.summaries,
          total: spans.length,
          deltaTokens: plan.freedTokens,
          tail,
        } as PruneDetails,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as PruneDetails | undefined;
      if (!d) return new Text("", 0, 0);
      if (!d.applied.length)
        return new Text(theme.fg("warning", "unknown id(s)"), 0, 0);
      // Full digest(s) untruncated: renderResult is TUI-only (never serialized
      // into context) and Text word-wraps, so it is free to display.
      const head =
        theme.fg("success", `✓ collapsed ${d.collapsed} msgs, freed ${fmtTokens(d.deltaTokens)}`) +
        theme.fg("dim", ` · ${d.tail}`);
      const body = d.summaries
        .filter((s) => s)
        .map((s) => theme.fg("dim", `→ ${s}`))
        .join("\n");
      return new Text(body ? `${head}\n${body}` : head, 0, 0);
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
          ? `− expanded ${plan.applied.length}: ${plan.applied.join(", ")}, +${fmtTokens(plan.restoredTokens)}${pctOf(plan.restoredTokens, win, "+")}`
          : "Expanded nothing") +
        (plan.noop.length ? `. not folded: ${plan.noop.join(", ")}` : "");
      return {
        content: [{ type: "text", text: `${head}\n${tail}` }],
        details: {
          action: "expand",
          applied: plan.applied,
          unknown: [],
          noop: plan.noop,
          collapsed: 0,
          summaries: [],
          total: spans.length,
          deltaTokens: plan.restoredTokens,
          tail,
        } as PruneDetails,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as PruneDetails | undefined;
      if (!d) return new Text("", 0, 0);
      return new Text(
        theme.fg("success", `✓ expanded ${d.applied.length}, +${fmtTokens(d.deltaTokens)}`) +
          theme.fg("dim", ` · ${d.tail}`),
        0,
        0,
      );
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
          details: { kind: "tree", totalSpans, hiddenTokens } as unknown,
        };
      }
      const span = spans.find(
        (s) => s.fromId === params.id || s.memberIds.includes(params.id!),
      );
      if (!span)
        return {
          content: [{ type: "text", text: `No fold for id ${params.id}.` }],
          details: { kind: "miss" } as unknown,
        };
      const body = serializeSpan(span, msgs);
      return {
        content: [
          {
            type: "text",
            text: `fold [#${span.fromId}] · ${span.memberIds.length} members:\n\n${body}`,
          },
        ],
        details: { kind: "span", fromId: span.fromId, members: span.memberIds.length } as unknown,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as { kind?: string; totalSpans?: number; members?: number } | undefined;
      if (!d) return new Text("", 0, 0);
      if (d.kind === "tree")
        return new Text(theme.fg("accent", `◈ ${d.totalSpans ?? 0} fold(s)`), 0, 0);
      if (d.kind === "span")
        return new Text(theme.fg("accent", `◈ peeked ${d.members ?? 0} members`), 0, 0);
      return new Text(theme.fg("warning", "no such fold"), 0, 0);
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
        details: { kind: "search", total, shown: hits.length } as unknown,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as { total?: number } | undefined;
      return new Text(theme.fg("accent", `⌕ ${d?.total ?? 0} hit(s)`), 0, 0);
    },
  });
}
