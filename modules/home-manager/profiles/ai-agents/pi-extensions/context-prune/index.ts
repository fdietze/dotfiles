/**
 * Context Prune - the agent edits its own context (imperative shell).
 *
 * Idea: in the `context` event every conversation message gets a visible
 * `[#id]` marker prepended (only for that LLM call, non-destructive). The agent
 * references messages by it and calls `forget` (forget a range, optionally with
 * a summary) or `remember` (restore).
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
  type Span,
  PRUNE_ENTRY,
  branchMessages,
  buildOverlay,
  planForget,
  planRemember,
  reconstructSpans,
  stripLeadingMarkers,
} from "./core.ts";

interface PruneDetails {
  action: "forget" | "remember";
  applied: string[];
  unknown: string[];
  noop: string[];
  collapsed: number;
  summaries: string[];
  total: number;
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

  // --- forget --------------------------------------------------------------

  const ForgetParam = Type.Object({
    items: Type.Array(
      Type.Object({
        from: Type.String({
          description:
            "Start id (the 8-char hex in a [#id] marker). For a single message, omit `to`.",
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
              "Optional digest that replaces the range — write it so you can resume from it alone, and hint what detail is inside so you can judge whether to `remember` it later. Omit to just drop the content (noise).",
          }),
        ),
      }),
      {
        description:
          "Ranges to forget, each { from, to?, summary? }. Multiple items = batch in one call.",
      },
    ),
  });

  pi.registerTool({
    name: "forget",
    label: "Forget",
    description:
      "Forget earlier messages to keep the model context lean — reversible. Pass a list of ranges by their " +
      "[#id] markers; each is { from, to?, summary? }. With `summary`, the range collapses into your " +
      "digest (use for finished sub-threads worth condensing). Without `summary`, the range's content is just " +
      "dropped (use for noise: tool outputs, detours, resolved debugging). `to` defaults to `from` for a single " +
      "message. Ranges snap outward to keep tool call/result pairs whole. Restore later with remember.",
    promptSnippet:
      "Forget/compact earlier messages via their [#id] markers to free context",
    promptGuidelines: [
      "`[#id]` markers are labels the system prepends to each message so you can reference it — they are NOT part of the message text. Never write a `[#id]` marker in your own replies. Use these ids only as arguments to `forget` / `remember`.",
      "Routinely forget finished sub-threads: pass a range with a short `summary` to condense it, or without `summary` to drop pure noise (tool outputs, detours, resolved debugging). Keeps the working context lean; reversible via `remember`.",
      "Write a `summary` you could resume from alone (without `remember`). Lead with open loops (unfinished work, pending decisions/commits/confirmations); then current state (what is now true — commit hashes, paths, passing tests); then decisions and why, including rejected options; then gotchas learned; and hint what detail sits inside the range so you can judge whether to `remember` it later. Be specific — name files, symbols, hashes; avoid vague verbs like 'fixed it'. Drop play-by-play and tool output. As terse as possible while still resumable.",
    ],
    parameters: ForgetParam,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const plan = planForget(branchMessages(branch(ctx)), spans, params.items);
      spans = plan.spans;
      if (plan.collapsed) persist();
      const text = plan.applied.length
        ? `Forgot ${plan.collapsed} message(s) into ${plan.applied.length} stub(s): ${plan.applied.join(", ")}` +
          (plan.unknown.length
            ? `. unknown id(s): ${plan.unknown.join(", ")}`
            : "")
        : `Forgot nothing. unknown id(s): ${plan.unknown.join(", ")}`;
      return {
        content: [{ type: "text", text }],
        details: {
          action: "forget",
          applied: plan.applied,
          unknown: plan.unknown,
          noop: [],
          collapsed: plan.collapsed,
          summaries: plan.summaries,
          total: spans.length,
        } as PruneDetails,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as PruneDetails | undefined;
      if (!d) return new Text("", 0, 0);
      if (!d.applied.length)
        return new Text(theme.fg("warning", "unknown id(s)"), 0, 0);
      // Show the full digest(s) untruncated: renderResult is TUI-only (never
      // serialized into context) and Text word-wraps, so it is free to display.
      const head =
        theme.fg("success", `✓ forgot ${d.collapsed} msg(s)`) +
        theme.fg("dim", ` (${d.total} total)`);
      const body = d.summaries
        .filter((s) => s)
        .map((s) => theme.fg("dim", `→ ${s}`))
        .join("\n");
      return new Text(body ? `${head}\n${body}` : head, 0, 0);
    },
  });

  // --- remember ------------------------------------------------------------

  const IdsParam = Type.Object({
    ids: Type.Array(Type.String(), {
      description:
        "Stub ids from their [#id] markers (the 8-char hex inside the brackets).",
    }),
  });

  pi.registerTool({
    name: "remember",
    label: "Remember",
    description:
      "Restore previously forgotten messages/ranges back into the model context by their [#id] markers " +
      "(the stub's id). Inverse of forget.",
    parameters: IdsParam,
    async execute(_id, params, _signal, _onUpdate, _ctx) {
      const plan = planRemember(spans, params.ids);
      spans = plan.spans;
      if (plan.applied.length) persist();
      const text =
        (plan.applied.length
          ? `Remembered ${plan.applied.length}: ${plan.applied.join(", ")}`
          : "Remembered nothing") +
        (plan.noop.length ? `. not forgotten: ${plan.noop.join(", ")}` : "");
      return {
        content: [{ type: "text", text }],
        details: {
          action: "remember",
          applied: plan.applied,
          unknown: [],
          noop: plan.noop,
          collapsed: 0,
          summaries: [],
          total: spans.length,
        } as PruneDetails,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as PruneDetails | undefined;
      if (!d) return new Text("", 0, 0);
      return new Text(
        theme.fg("success", `✓ remembered ${d.applied.length}`) +
          theme.fg("dim", ` (${d.total} still forgotten)`),
        0,
        0,
      );
    },
  });
}
