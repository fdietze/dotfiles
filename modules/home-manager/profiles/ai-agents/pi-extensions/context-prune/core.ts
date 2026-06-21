/**
 * Context Prune - pure logic (functional core).
 *
 * No imports from pi packages: every function is a pure transformation over
 * plain data structures, so it is testable in isolation via node:test
 * (core.test.ts). The imperative shell (index.ts) wires pi events/tools and
 * calls into here.
 *
 * ONE mechanism: every forget is a `Span` (a range snapped to whole tool units)
 * with an optional summary. A span with a single member and an empty summary is
 * the former "tombstone" (content gone, stub remains). Because spans always
 * cover whole toolCall/toolResult units (expandRange), replacing them with a
 * single synthetic user message can never orphan a pair. Everything is fully
 * reversible (remember).
 */

// Custom-entry type for the persisted span list.
export const PRUNE_ENTRY = "context-prune";

// Roles that get a visible marker and can be forgotten.
export const TAGGABLE_ROLES = new Set(["user", "assistant", "toolResult"]);

export type Content = string | Array<{ type?: string; text?: string }>;
export interface AgentMessageLike {
  role: string;
  content: Content;
  timestamp?: number;
  details?: unknown;
  toolCallId?: string;
  toolName?: string;
  isError?: boolean;
}

// Minimal shape of a session branch entry (only what the logic needs), so the
// core stays free of pi types.
export interface BranchEntry {
  type: string;
  id?: string;
  customType?: string;
  data?: unknown;
  message?: AgentMessageLike;
}

export type BranchMsg = { id: string; message: AgentMessageLike };

// A forgotten range: its stub message inherits fromId (= first member) as the
// visible id, so it can itself be folded into another range and resolved again
// via remember. memberIds are always real entry ids (flat), contiguous and
// ascending in branch order. summary == "" -> the range is only dropped (stub
// "(forgotten N)"), otherwise it is replaced by the summary.
export interface Span {
  fromId: string;
  memberIds: string[];
  summary: string;
}

// Marker the agent reads and passes back to collapse/expand. The plain form is
// the reference token (stubs, tool args); live messages additionally carry a
// size via sizedMarker so the model can spot the fat ones to collapse.
export const marker = (id: string) => `[#${id}]`;
export const sizedMarker = (id: string, tokens: number) =>
  `[#${id} ${fmtTokens(tokens)}]`;

/**
 * Compact token label: <1000 -> "340"; else one-decimal k with trailing ".0"
 * dropped ("1.2k", "12k"). Single formatter (DRY) for markers, stubs, tails, peek.
 */
export function fmtTokens(n: number): string {
  if (n < 1000) return String(n);
  return `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k`;
}

/** Sum of content chars across the shapes we see (text/thinking/toolCall). */
function messageChars(message: AgentMessageLike): number {
  const c = message.content;
  if (typeof c === "string") return c.length;
  if (!Array.isArray(c)) return 0;
  let chars = 0;
  for (const block of c as Array<Record<string, unknown>>) {
    if (typeof block.text === "string") chars += block.text.length;
    if (typeof block.thinking === "string") chars += block.thinking.length;
    if (block.type === "toolCall") {
      if (typeof block.name === "string") chars += block.name.length;
      if ("arguments" in block) chars += JSON.stringify(block.arguments).length;
    }
  }
  return chars;
}

/**
 * Conservative chars/4 token estimate, mirroring pi's exported estimateTokens
 * (compaction.ts). Reimplemented here to keep the core free of pi imports
 * (testable in isolation). Used for the per-message marker size and all
 * freed/hidden/restored token math.
 */
export function estimateTokens(message: AgentMessageLike): number {
  return Math.ceil(messageChars(message) / 4);
}

/** Plain text of a message's content, for peek serialization. */
export function serializeContent(message: AgentMessageLike): string {
  const c = message.content;
  if (typeof c === "string") return c;
  if (!Array.isArray(c)) return "";
  const parts: string[] = [];
  for (const block of c as Array<Record<string, unknown>>) {
    if (typeof block.text === "string") parts.push(block.text);
    else if (typeof block.thinking === "string")
      parts.push(`(thinking) ${block.thinking}`);
    else if (block.type === "toolCall")
      parts.push(`(call ${block.name ?? "?"} ${JSON.stringify(block.arguments ?? {})})`);
  }
  return parts.join("\n");
}

// Leading [#8hex] markers the model imitates in its own output. Prompt
// instructions do not prevent this: empirically ~85% imitation across
// haiku-4-5 and sonnet-4-5 (3 prompt variants tested, incl. few-shot), because
// first-token pattern continuation beats instructions; it also accumulates (up
// to ~30 markers/message). So strip them at the output boundary (message_end)
// -> fakes are never persisted and cannot accumulate. Leading/positional only:
// an id referenced mid-prose (e.g. "forgetting [#abc12345]") is kept.
// Widened to also swallow the optional ` 1.2k` size inside the bracket, so the
// sizedMarker form the model imitates is stripped too.
export const LEADING_FAKE_MARKERS =
  /^(?:\s*\[#[0-9a-f]{8}(?:\s+[0-9.]+k?)?\]\s*)+/;

export function stripLeadingMarkers(
  message: AgentMessageLike,
): AgentMessageLike {
  if (typeof message.content === "string") {
    const stripped = message.content.replace(LEADING_FAKE_MARKERS, "");
    return stripped === message.content
      ? message
      : { ...message, content: stripped };
  }
  if (Array.isArray(message.content)) {
    const idx = message.content.findIndex((b) => b?.type === "text");
    if (idx < 0) return message;
    const block = message.content[idx];
    const stripped = (block.text ?? "").replace(LEADING_FAKE_MARKERS, "");
    if (stripped === block.text) return message;
    const content = message.content.slice();
    content[idx] = { ...block, text: stripped };
    return { ...message, content };
  }
  return message;
}

/** Prepend the visible sized `[#id 1.2k]` marker to the first text block. */
export function tag(
  message: AgentMessageLike,
  id: string,
  tokens: number,
): void {
  const m = sizedMarker(id, tokens);
  const prefix = `${m} `;
  // Also strip already-persisted fakes from old sessions while tagging
  // (message_end only catches new messages). assistant only, since only the
  // model imitates markers; user/toolResult text is left untouched.
  const clean = (t: string) =>
    message.role === "assistant" ? t.replace(LEADING_FAKE_MARKERS, "") : t;
  if (typeof message.content === "string") {
    message.content = prefix + clean(message.content);
    return;
  }
  const blocks = message.content;
  const textIdx = blocks.findIndex((b) => b?.type === "text");
  if (textIdx >= 0) {
    blocks[textIdx] = {
      ...blocks[textIdx],
      text: prefix + clean(blocks[textIdx].text ?? ""),
    };
    return;
  }
  // No text block (e.g. assistant with only a toolCall): insert after any
  // leading thinking blocks so the provider block order stays valid.
  let insertAt = 0;
  while (insertAt < blocks.length && blocks[insertAt]?.type === "thinking")
    insertAt++;
  blocks.splice(insertAt, 0, { type: "text", text: m });
}

/** Ordered, taggable message entries of the branch (branch order). */
export function branchMessages(branch: BranchEntry[]): BranchMsg[] {
  const out: BranchMsg[] = [];
  for (const entry of branch) {
    if (entry.type === "message" && entry.message && entry.id !== undefined) {
      if (TAGGABLE_ROLES.has(entry.message.role))
        out.push({ id: entry.id, message: entry.message });
    }
  }
  return out;
}

/**
 * Per position, the [start,end] bounds of the atomic toolCall/toolResult unit.
 * A unit = an assistant message with toolCall blocks + every toolResult message
 * answering its call ids (a turn can have several). Messages outside a unit have
 * start==end==their own index.
 */
export function unitBounds(msgs: BranchMsg[]): {
  start: number[];
  end: number[];
} {
  const n = msgs.length;
  const start = Array.from({ length: n }, (_, i) => i);
  const end = Array.from({ length: n }, (_, i) => i);
  const callOwner = new Map<string, number>(); // toolCall block id -> assistant index
  for (let i = 0; i < n; i++) {
    const m = msgs[i].message;
    if (m.role === "assistant" && Array.isArray(m.content)) {
      for (const b of m.content as Array<{ type?: string; id?: string }>) {
        if (b?.type === "toolCall" && b.id) callOwner.set(b.id, i);
      }
    }
  }
  const resultsByOwner = new Map<number, number[]>(); // assistant index -> result indices
  for (let i = 0; i < n; i++) {
    const m = msgs[i].message;
    if (m.role === "toolResult" && m.toolCallId) {
      const a = callOwner.get(m.toolCallId);
      if (a !== undefined)
        (resultsByOwner.get(a) ?? resultsByOwner.set(a, []).get(a)!).push(i);
    }
  }
  for (const [a, rs] of resultsByOwner) {
    const e = Math.max(a, ...rs);
    start[a] = a;
    end[a] = e;
    for (const r of rs) {
      start[r] = a;
      end[r] = e;
    }
  }
  return { start, end };
}

/**
 * First snap lo/hi to whole tool units, then flatly absorb overlapping spans
 * (fully include their members). Repeat until stable.
 */
export function expandRange(
  msgs: BranchMsg[],
  bounds: { start: number[]; end: number[] },
  spans: Span[],
  loIn: number,
  hiIn: number,
): { lo: number; hi: number } {
  let lo = loIn;
  let hi = hiIn;
  const indexById = new Map(msgs.map((m, i) => [m.id, i] as const));
  let changed = true;
  while (changed) {
    changed = false;
    for (let i = lo; i <= hi; i++) {
      if (bounds.start[i] < lo) {
        lo = bounds.start[i];
        changed = true;
      }
      if (bounds.end[i] > hi) {
        hi = bounds.end[i];
        changed = true;
      }
    }
    for (const span of spans) {
      const idxs = span.memberIds
        .map((id) => indexById.get(id))
        .filter((x): x is number => x !== undefined);
      if (idxs.some((x) => x >= lo && x <= hi)) {
        const sLo = Math.min(...idxs);
        const sHi = Math.max(...idxs);
        if (sLo < lo) {
          lo = sLo;
          changed = true;
        }
        if (sHi > hi) {
          hi = sHi;
          changed = true;
        }
      }
    }
  }
  return { lo, hi };
}

export interface CollapseItem {
  from: string;
  to?: string;
  summary?: string;
}

export interface CollapsePlan {
  spans: Span[]; // new span state (the input is left unchanged)
  applied: string[]; // fromIds of the resulting stubs (deduplicated)
  summaries: string[]; // summary per applied stub
  collapsed: number; // distinct collapsed messages
  unknown: string[]; // ids that could not be resolved
  freedTokens: number; // net context tokens freed (live members - new stubs)
}

/** What buildOverlay renders as a span's stub text (sans the [#id] marker). */
function stubText(summary: string, n: number, hidden: number): string {
  const h = fmtTokens(hidden);
  return summary
    ? `(summary, ${h} hidden) ${summary}`
    : `(forgotten ${n} message${n > 1 ? "s" : ""}, ${h} hidden)`;
}

/**
 * Pure forget planning. Returns the new span state + report without mutating
 * the input. Multiple items that snap to the same tool unit (e.g. parallel tool
 * calls in ONE assistant turn) merge into one stub; non-empty summaries are
 * kept (an empty one never overwrites a real one). The report is derived from
 * the final state -> deduplicated and counted correctly no matter how many
 * items coincided.
 */
export function planCollapse(
  msgs: BranchMsg[],
  spans: Span[],
  items: CollapseItem[],
): CollapsePlan {
  const next: Span[] = spans.map((s) => ({
    ...s,
    memberIds: s.memberIds.slice(),
  }));
  const indexById = new Map(msgs.map((m, i) => [m.id, i] as const));
  const tokById = new Map(
    msgs.map((m) => [m.id, estimateTokens(m.message)] as const),
  );
  // Members already folded before this call do not count as newly freed.
  const priorMembers = new Set(spans.flatMap((s) => s.memberIds));
  const bounds = unitBounds(msgs);
  const unknown: string[] = [];
  const touched = new Set<string>();
  for (const item of items) {
    // Spans mutate per item -> rebuild the lookup each time.
    const spanByFrom = new Map(next.map((s) => [s.fromId, s] as const));
    const startIdx = (id: string) => {
      const s = spanByFrom.get(id);
      return indexById.get(s ? s.memberIds[0] : id);
    };
    const endIdx = (id: string) => {
      const s = spanByFrom.get(id);
      return indexById.get(s ? s.memberIds[s.memberIds.length - 1] : id);
    };
    const toId = item.to ?? item.from;
    const a = startIdx(item.from);
    const b = endIdx(toId);
    if (a === undefined) unknown.push(item.from);
    if (b === undefined && toId !== item.from) unknown.push(toId);
    if (a === undefined || b === undefined) continue;
    const { lo, hi } = expandRange(
      msgs,
      bounds,
      next,
      Math.min(a, b),
      Math.max(a, b),
    );
    const memberIds = msgs.slice(lo, hi + 1).map((m) => m.id);
    const memberSet = new Set(memberIds);
    // Absorb overlapping/coinciding spans; inherit their non-empty summaries.
    const inherited: string[] = [];
    for (let i = next.length - 1; i >= 0; i--) {
      if (next[i].memberIds.some((id) => memberSet.has(id))) {
        if (next[i].summary) inherited.unshift(next[i].summary);
        next.splice(i, 1);
      }
    }
    const summary = [...inherited, item.summary ?? ""]
      .filter((s) => s)
      .join("; ");
    next.push({ fromId: memberIds[0], memberIds, summary });
    for (const id of memberIds) touched.add(id);
  }
  const resultSpans = next.filter((s) =>
    s.memberIds.some((id) => touched.has(id)),
  );
  // freed = newly-hidden live members minus the stub(s) that replace them.
  // Members folded by a prior span are excluded (already saved).
  let freedTokens = 0;
  for (const s of resultSpans) {
    const hidden = s.memberIds.reduce((t, id) => t + (tokById.get(id) ?? 0), 0);
    const live = s.memberIds.reduce(
      (t, id) => t + (priorMembers.has(id) ? 0 : (tokById.get(id) ?? 0)),
      0,
    );
    const stubTok = Math.ceil(
      stubText(s.summary, s.memberIds.length, hidden).length / 4,
    );
    freedTokens += live - stubTok;
  }
  return {
    spans: next,
    applied: resultSpans.map((s) => s.fromId),
    summaries: resultSpans.map((s) => s.summary),
    collapsed: touched.size,
    unknown,
    freedTokens,
  };
}

export interface ExpandItem {
  from: string;
  to?: string;
}

export interface ExpandPlan {
  spans: Span[];
  applied: string[]; // fromId of each restored sub-range
  noop: string[]; // ids matching no span
  restoredTokens: number; // context tokens brought back live
}

/**
 * Pure expand planning (inverse of collapse). Range-aware: an item is matched to
 * the span containing `from` (its stub fromId, or any inner member id revealed
 * by peek). A bare span fromId (no `to`) expands the WHOLE span; an explicit
 * from/to sub-range SPLITS the span - the sub-range is restored live, the two
 * leftover halves stay folded, both inheriting the original summary (lossless).
 * The sub-range is snapped to whole tool units and clamped within the span, so
 * remnants never orphan a tool call/result pair.
 */
export function planExpand(
  msgs: BranchMsg[],
  spans: Span[],
  items: ExpandItem[],
): ExpandPlan {
  const next: Span[] = spans.map((s) => ({
    ...s,
    memberIds: s.memberIds.slice(),
  }));
  const indexById = new Map(msgs.map((m, i) => [m.id, i] as const));
  const tokById = new Map(
    msgs.map((m) => [m.id, estimateTokens(m.message)] as const),
  );
  const bounds = unitBounds(msgs);
  const applied: string[] = [];
  const noop: string[] = [];
  let restoredTokens = 0;
  for (const item of items) {
    const si = next.findIndex(
      (s) => s.fromId === item.from || s.memberIds.includes(item.from),
    );
    if (si < 0) {
      noop.push(item.from);
      continue;
    }
    const span = next[si];
    const wholeSpan = item.to === undefined && item.from === span.fromId;
    const subFromId = wholeSpan ? span.memberIds[0] : item.from;
    const subToId = wholeSpan
      ? span.memberIds[span.memberIds.length - 1]
      : (item.to ?? item.from);
    const ai = indexById.get(subFromId);
    const bi = indexById.get(subToId);
    if (ai === undefined || bi === undefined) {
      noop.push(item.from);
      continue;
    }
    // Snap to whole tool units, clamped to the span's own member index range.
    const memberIdx = span.memberIds.map((id) => indexById.get(id)!);
    const spanLo = Math.min(...memberIdx);
    const spanHi = Math.max(...memberIdx);
    let lo = Math.min(ai, bi);
    let hi = Math.max(ai, bi);
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = lo; i <= hi; i++) {
        if (bounds.start[i] >= spanLo && bounds.start[i] < lo) {
          lo = bounds.start[i];
          changed = true;
        }
        if (bounds.end[i] <= spanHi && bounds.end[i] > hi) {
          hi = bounds.end[i];
          changed = true;
        }
      }
    }
    const left: string[] = [];
    const right: string[] = [];
    const restored: string[] = [];
    for (const id of span.memberIds) {
      const idx = indexById.get(id)!;
      if (idx < lo) left.push(id);
      else if (idx > hi) right.push(id);
      else restored.push(id);
    }
    if (restored.length === 0) {
      noop.push(item.from);
      continue;
    }
    next.splice(si, 1);
    if (left.length)
      next.push({ fromId: left[0], memberIds: left, summary: span.summary });
    if (right.length)
      next.push({ fromId: right[0], memberIds: right, summary: span.summary });
    applied.push(restored[0]);
    for (const id of restored) restoredTokens += tokById.get(id) ?? 0;
  }
  return { spans: next, applied, noop, restoredTokens };
}

/**
 * Overview of the fold tree: totals + one line per span (branch order). Used by
 * peek() and the collapse/expand result tails.
 */
export function summarizeTree(
  spans: Span[],
  msgs: BranchMsg[],
): { totalSpans: number; hiddenTokens: number; lines: string[] } {
  const tokById = new Map(
    msgs.map((m) => [m.id, estimateTokens(m.message)] as const),
  );
  const idxById = new Map(msgs.map((m, i) => [m.id, i] as const));
  const ordered = spans
    .slice()
    .sort(
      (a, b) =>
        (idxById.get(a.memberIds[0]) ?? 0) - (idxById.get(b.memberIds[0]) ?? 0),
    );
  let hiddenTokens = 0;
  const lines = ordered.map((s) => {
    const tok = s.memberIds.reduce((t, id) => t + (tokById.get(id) ?? 0), 0);
    hiddenTokens += tok;
    const n = s.memberIds.length;
    const label = s.summary
      ? s.summary.length > 60
        ? `${s.summary.slice(0, 60)}…`
        : s.summary
      : "(no summary)";
    return `[#${s.fromId}] · ${n} msg${n > 1 ? "s" : ""} · ${fmtTokens(tok)} · ${label}`;
  });
  return { totalSpans: spans.length, hiddenTokens, lines };
}

/**
 * Serialize a span's hidden members for peek(id): per message its inner id,
 * role, size and content (capped, so peeking a fat span can't blow the budget).
 */
export function serializeSpan(
  span: Span,
  msgs: BranchMsg[],
  cap = 2000,
): string {
  const byId = new Map(msgs.map((m) => [m.id, m.message] as const));
  const out: string[] = [];
  for (const id of span.memberIds) {
    const m = byId.get(id);
    if (!m) continue;
    const text = serializeContent(m);
    const body =
      text.length > cap
        ? `${text.slice(0, cap)}… [+${text.length - cap} chars]`
        : text;
    out.push(`[#${id}] ${m.role} ${fmtTokens(estimateTokens(m))}\n${body}`);
  }
  return out.join("\n\n");
}

/**
 * Reconstruct the span list from the branch. The last custom entry wins
 * (cumulative snapshot). Old sessions with a `pruned` list -> single-member spans.
 */
export function reconstructSpans(branch: BranchEntry[]): Span[] {
  let spans: Span[] = [];
  for (const entry of branch) {
    if (entry.type === "custom" && entry.customType === PRUNE_ENTRY) {
      const data = entry.data as
        | { pruned?: string[]; spans?: Span[] }
        | undefined;
      spans = [];
      for (const s of data?.spans ?? []) spans.push(s);
      for (const id of data?.pruned ?? [])
        spans.push({ fromId: id, memberIds: [id], summary: "" });
    }
  }
  return spans;
}

/**
 * Build the context overlay: inject markers, or replace forgotten ranges with a
 * stub. Deterministic (stable prompt caching). Mutates the replaced message
 * objects in `messages` in place (like the pi context handler).
 */
export function buildOverlay(
  messages: AgentMessageLike[],
  branch: BranchEntry[],
  spans: Span[],
): AgentMessageLike[] {
  // Entry ids in branch order per (timestamp,role) as a queue, to consume equal
  // keys position-stably.
  const idQueues = new Map<string, string[]>();
  // Per entry id, its estimated token footprint (from the branch message, which
  // matches event.messages content). Used for live markers and stub hidden-cost.
  const idTokens = new Map<string, number>();
  for (const entry of branch) {
    if (entry.type !== "message" || !entry.message || entry.id === undefined)
      continue;
    const msg = entry.message;
    if (!TAGGABLE_ROLES.has(msg.role)) continue;
    const key = `${msg.timestamp}|${msg.role}`;
    const queue = idQueues.get(key) ?? idQueues.set(key, []).get(key)!;
    queue.push(entry.id);
    idTokens.set(entry.id, estimateTokens(msg));
  }

  const spanByFrom = new Map(spans.map((s) => [s.fromId, s] as const));
  const hiddenMembers = new Set<string>();
  for (const s of spans)
    for (const id of s.memberIds.slice(1)) hiddenMembers.add(id);

  const out: AgentMessageLike[] = [];
  for (const message of messages) {
    if (!TAGGABLE_ROLES.has(message.role)) {
      out.push(message);
      continue;
    }
    const id = idQueues.get(`${message.timestamp}|${message.role}`)?.shift();
    if (!id) {
      out.push(message);
      continue;
    }
    if (hiddenMembers.has(id)) continue; // non-first member of a span -> drop
    const span = spanByFrom.get(id);
    if (span) {
      const n = span.memberIds.length;
      const hidden = span.memberIds.reduce(
        (t, m) => t + (idTokens.get(m) ?? 0),
        0,
      );
      message.role = "user";
      message.content = `${marker(id)} ${stubText(span.summary, n, hidden)}`;
      message.details = undefined;
      message.toolCallId = undefined;
      out.push(message);
      continue;
    }
    tag(message, id, idTokens.get(id) ?? estimateTokens(message));
    out.push(message);
  }
  return out;
}
