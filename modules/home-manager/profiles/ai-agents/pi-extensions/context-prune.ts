/**
 * Context Prune - der Agent bearbeitet seinen eigenen Kontext.
 *
 * Idee: Jede Conversation-Message bekommt im `context`-Event (nur fuer den
 * jeweiligen LLM-Call, non-destruktiv) einen sichtbaren `[#id]`-Marker
 * vorangestellt. Der Agent referenziert damit Messages und ruft
 * `forget_messages({ ids })` bzw. `recall_messages({ ids })`.
 *
 * Warum Marker im Text statt im JSON: Der Provider serialisiert nur `role` +
 * `content`; Zusatzfelder am Message-Objekt erreichen das Modell nie. Die
 * Entry-`id` lebt zudem nur am Session-*Entry* (getBranch()), nicht an der
 * AgentMessage (siehe docs/session-format.md). Deshalb wird im context-Handler
 * Entry<->Message ueber `timestamp`+`role` korreliert (gemeinsamer, 1:1
 * kopierter Schluessel), dann der Marker in den ersten Text-Block gepatcht.
 *
 * Warum "vergessen" = Tombstone statt echtes Entfernen: toolCall/toolResult
 * sind gepaart; ein hartes Entfernen wuerde Paare verwaisen lassen (Provider-
 * Fehler) oder die Rollen-Alternation brechen. Der Tombstone ersetzt nur den
 * (grossen) Content, behaelt die Struktur und ist voll reversibel.
 *
 * Persistenz: Der kumulative Pruned-Set wird via pi.appendEntry als Custom-
 * Entry in die Session geschrieben und in session_start/session_tree wieder
 * rekonstruiert (analog examples/extensions/todo.ts) -> ueberlebt /reload und
 * folgt korrekt der Branch-History.
 *
 * Doku: docs/extensions.md ("context" event, registerTool, appendEntry),
 *       docs/session-format.md (Entry/Message-Typen, getBranch, ids).
 */

import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

// Custom-Entry-Typ fuer die persistierte Pruned-Liste.
const PRUNE_ENTRY = "context-prune";

// Rollen, die einen sichtbaren Marker bekommen und vergessen werden koennen.
const TAGGABLE_ROLES = new Set(["user", "assistant", "toolResult"]);

type Content = string | Array<{ type?: string; text?: string }>;
interface AgentMessageLike {
  role: string;
  content: Content;
  timestamp?: number;
  details?: unknown;
  toolCallId?: string;
  toolName?: string;
  isError?: boolean;
}

interface PruneDetails {
  action: "forget" | "recall";
  applied: string[];
  unknown: string[];
  noop: string[];
  total: number;
}

// Eine zusammengefasste Range: ihre Summary-Message erbt fromId (= erstes
// Member) als sichtbare id, damit sie selbst wieder in eine Range aufgenommen
// und per recall aufgeloest werden kann. memberIds sind immer echte Entry-ids
// (flach), zusammenhaengend und in Branch-Reihenfolge aufsteigend.
interface Span {
  fromId: string;
  memberIds: string[];
  summary: string;
}

// Marker, den der Agent liest und an forget/recall zurueckgibt.
const marker = (id: string) => `[#${id}]`;

/** Sichtbaren `[#id]`-Marker an den ersten Text-Block voranstellen. */
function tag(message: AgentMessageLike, id: string): void {
  const prefix = `${marker(id)} `;
  if (typeof message.content === "string") {
    message.content = prefix + message.content;
    return;
  }
  const blocks = message.content;
  const textIdx = blocks.findIndex((b) => b?.type === "text");
  if (textIdx >= 0) {
    blocks[textIdx] = {
      ...blocks[textIdx],
      text: prefix + (blocks[textIdx].text ?? ""),
    };
    return;
  }
  // Kein Text-Block (z.B. Assistant nur mit toolCall): nach fuehrenden
  // thinking-Bloecken einfuegen, damit die Provider-Reihenfolge stimmt.
  let insertAt = 0;
  while (insertAt < blocks.length && blocks[insertAt]?.type === "thinking")
    insertAt++;
  blocks.splice(insertAt, 0, { type: "text", text: marker(id) });
}

/**
 * Content durch einen Tombstone ersetzen. Erhaelt Pairing/Struktur:
 * - toolResult: Output blanken, toolCallId/Rolle bleiben -> Paar intakt.
 * - assistant: toolCall-Bloecke behalten (klein, fuer Pairing noetig),
 *   Text/Thinking durch Marker ersetzen.
 * - user/sonst: kompletter Content -> Marker.
 */
function tombstone(message: AgentMessageLike, id: string): void {
  const note = `${marker(id)} (forgotten)`;
  if (message.role === "toolResult") {
    message.content = [{ type: "text", text: note }];
    message.details = undefined;
    return;
  }
  if (message.role === "assistant" && Array.isArray(message.content)) {
    const toolCalls = message.content.filter((b) => b?.type === "toolCall");
    message.content = [{ type: "text", text: note }, ...toolCalls];
    return;
  }
  message.content = note;
}

/** Geordnete, taggbare Message-Entries des aktuellen Branch (Branch-Reihenfolge). */
function branchMessages(
  ctx: ExtensionContext,
): { id: string; message: AgentMessageLike }[] {
  const out: { id: string; message: AgentMessageLike }[] = [];
  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type === "message") {
      const m = entry.message as AgentMessageLike;
      if (TAGGABLE_ROLES.has(m.role)) out.push({ id: entry.id, message: m });
    }
  }
  return out;
}

/**
 * Pro Position die [start,end]-Grenzen der atomaren toolCall/toolResult-Einheit.
 * Eine Einheit = Assistant-Message mit toolCall-Bloecken + alle toolResult-
 * Messages, die deren call-ids beantworten (ein Turn kann mehrere haben).
 * Messages ausserhalb einer Einheit haben start==end==eigener Index.
 */
function unitBounds(msgs: { id: string; message: AgentMessageLike }[]): {
  start: number[];
  end: number[];
} {
  const n = msgs.length;
  const start = Array.from({ length: n }, (_, i) => i);
  const end = Array.from({ length: n }, (_, i) => i);
  const callOwner = new Map<string, number>(); // toolCall-Block-id -> Assistant-Index
  for (let i = 0; i < n; i++) {
    const m = msgs[i].message;
    if (m.role === "assistant" && Array.isArray(m.content)) {
      for (const b of m.content as Array<{ type?: string; id?: string }>) {
        if (b?.type === "toolCall" && b.id) callOwner.set(b.id, i);
      }
    }
  }
  const resultsByOwner = new Map<number, number[]>(); // Assistant-Index -> Result-Indizes
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
 * lo/hi zuerst auf ganze Tool-Einheiten snappen, dann ueberlappende Spans
 * flach absorbieren (deren Member ganz einschliessen). Wiederholt bis stabil.
 */
function expandRange(
  msgs: { id: string; message: AgentMessageLike }[],
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

export default function (pi: ExtensionAPI) {
  // In-memory Quelle der Wahrheit, aus der Session rekonstruiert.
  const pruned = new Set<string>();
  const spans: Span[] = [];

  const reconstruct = (ctx: ExtensionContext) => {
    pruned.clear();
    spans.length = 0;
    // Letzter Custom-Entry auf dem Branch gewinnt (kumulativer Snapshot).
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type === "custom" && entry.customType === PRUNE_ENTRY) {
        const data = entry.data as
          | { pruned?: string[]; spans?: Span[] }
          | undefined;
        pruned.clear();
        spans.length = 0;
        for (const id of data?.pruned ?? []) pruned.add(id);
        for (const s of data?.spans ?? []) spans.push(s);
      }
    }
  };
  const persist = () =>
    pi.appendEntry(PRUNE_ENTRY, { pruned: [...pruned], spans });

  pi.on("session_start", async (_event, ctx) => reconstruct(ctx));
  pi.on("session_tree", async (_event, ctx) => reconstruct(ctx));

  // Marker injizieren bzw. vergessene Messages tombstonen - jedes Mal
  // deterministisch, damit das Prompt-Caching stabil bleibt.
  pi.on("context", async (event, ctx) => {
    // Entry-ids in Branch-Reihenfolge pro (timestamp,role) als Queue, um
    // gleiche Schluessel positionsstabil zu konsumieren.
    const idQueues = new Map<string, string[]>();
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== "message") continue;
      const msg = entry.message as AgentMessageLike;
      if (!TAGGABLE_ROLES.has(msg.role)) continue;
      const key = `${msg.timestamp}|${msg.role}`;
      const queue = idQueues.get(key) ?? idQueues.set(key, []).get(key)!;
      queue.push(entry.id);
    }

    // Span-Lookups: fromId -> Span (durch Summary ersetzen), uebrige Member weglassen.
    const spanByFrom = new Map(spans.map((s) => [s.fromId, s] as const));
    const hiddenMembers = new Set<string>();
    for (const s of spans)
      for (const id of s.memberIds.slice(1)) hiddenMembers.add(id);

    const out: AgentMessageLike[] = [];
    for (const message of event.messages as AgentMessageLike[]) {
      if (!TAGGABLE_ROLES.has(message.role)) {
        out.push(message);
        continue;
      }
      const id = idQueues.get(`${message.timestamp}|${message.role}`)?.shift();
      if (!id) {
        out.push(message);
        continue;
      }
      if (hiddenMembers.has(id)) continue; // Teil eines Spans (nicht erstes Member) -> weglassen
      const span = spanByFrom.get(id);
      if (span) {
        // Ganze Range durch EINE synthetische user-Summary ersetzen. Da der Span
        // immer ganze Tool-Einheiten umfasst, koennen die weggelassenen Member
        // nie ein toolCall/toolResult-Paar verwaisen lassen.
        message.role = "user";
        message.content = `${marker(id)} (summary) ${span.summary}`;
        message.details = undefined;
        message.toolCallId = undefined;
        out.push(message);
        continue;
      }
      if (pruned.has(id)) tombstone(message, id);
      else tag(message, id);
      out.push(message);
    }
    return { messages: out };
  });

  // Gueltige (vergessbare) Message-Entry-ids auf dem aktuellen Branch.
  const validIds = (ctx: ExtensionContext): Set<string> => {
    const ids = new Set<string>();
    for (const entry of ctx.sessionManager.getBranch()) {
      if (
        entry.type === "message" &&
        TAGGABLE_ROLES.has((entry.message as AgentMessageLike).role)
      ) {
        ids.add(entry.id);
      }
    }
    return ids;
  };

  const summarize = (
    action: "forget" | "recall",
    applied: string[],
    unknown: string[],
    noop: string[],
  ): string => {
    const parts: string[] = [];
    const verb = action === "forget" ? "Forgot" : "Recalled";
    parts.push(
      applied.length
        ? `${verb} ${applied.length} message(s): ${applied.join(", ")}`
        : `${verb} nothing`,
    );
    if (noop.length)
      parts.push(
        `already ${action === "forget" ? "forgotten" : "active"}: ${noop.join(", ")}`,
      );
    if (unknown.length) parts.push(`unknown id(s): ${unknown.join(", ")}`);
    return parts.join(". ");
  };

  const IdsParam = Type.Object({
    ids: Type.Array(Type.String(), {
      description:
        "Message ids from their [#id] markers (the 8-char hex inside the brackets).",
    }),
  });

  pi.registerTool({
    name: "forget_messages",
    label: "Forget Messages",
    description:
      "Drop the content of earlier messages from the model context by their [#id] markers. Do this regularly to keep the context clean." +
      "Good candidates: Tool calls, superseded exchanges, detours, resolving ambiguities, debugging sessions, the discussion messages leading to a final result. Reversible via recall_messages to look up details.",
    promptSnippet:
      "Free context by forgetting earlier messages via their [#id] markers",
    promptGuidelines: [
      "Every message is prefixed with a [#id] marker before sending it to the llm API; Don't generate message ids yourself, as there will be one prefixed automatically. pass those ids to forget_messages to create an overlay for that range which is sent to llm API instead of the original content. Or recall_messages to restore them (removes the overlay).",
    ],
    parameters: IdsParam,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const valid = validIds(ctx);
      const applied: string[] = [];
      const unknown: string[] = [];
      const noop: string[] = [];
      for (const id of params.ids) {
        if (!valid.has(id)) unknown.push(id);
        else if (pruned.has(id)) noop.push(id);
        else {
          pruned.add(id);
          applied.push(id);
        }
      }
      if (applied.length) persist();
      return {
        content: [
          { type: "text", text: summarize("forget", applied, unknown, noop) },
        ],
        details: {
          action: "forget",
          applied,
          unknown,
          noop,
          total: pruned.size + spans.length,
        } as PruneDetails,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as PruneDetails | undefined;
      if (!d) return new Text("", 0, 0);
      return new Text(
        theme.fg("success", `✓ forgot ${d.applied.length}`) +
          theme.fg("dim", ` (${d.total} total)`),
        0,
        0,
      );
    },
  });

  pi.registerTool({
    name: "recall_messages",
    label: "Recall Messages",
    description:
      "Restore previously forgotten messages back into context by their [#id] markers.",
    parameters: IdsParam,
    async execute(_id, params, _signal, _onUpdate, _ctx) {
      const applied: string[] = [];
      const noop: string[] = [];
      for (const id of params.ids) {
        if (pruned.delete(id)) {
          applied.push(id);
          continue;
        }
        // id koennte die fromId eines Spans sein -> Span aufloesen (flach: alle Originale zurueck).
        const i = spans.findIndex((s) => s.fromId === id);
        if (i >= 0) {
          spans.splice(i, 1);
          applied.push(id);
        } else {
          noop.push(id);
        }
      }
      if (applied.length) persist();
      return {
        content: [
          { type: "text", text: summarize("recall", applied, [], noop) },
        ],
        details: {
          action: "recall",
          applied,
          unknown: [],
          noop,
          total: pruned.size + spans.length,
        } as PruneDetails,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as PruneDetails | undefined;
      if (!d) return new Text("", 0, 0);
      return new Text(
        theme.fg("success", `✓ recalled ${d.applied.length}`) +
          theme.fg("dim", ` (${d.total} forgotten)`),
        0,
        0,
      );
    },
  });

  const FromToParam = Type.Object({
    from: Type.String({
      description:
        "Start id (the 8-char hex in a [#id] marker); a real message or an existing summary's id.",
    }),
    to: Type.String({
      description:
        "End id (the 8-char hex in a [#id] marker), inclusive. Order relative to `from` does not matter.",
    }),
    summary: Type.String({
      description: "Short summary text that replaces the whole range.",
    }),
  });

  pi.registerTool({
    name: "forget_range",
    label: "Forget Range",
    description:
      "Collapse a contiguous range of messages (from..to, inclusive, by their [#id] markers) into a single " +
      "summary you write. Reclaims context on finished sub-threads. The range snaps outward to keep tool " +
      "call/result pairs whole. Reversible via recall_messages.",
    promptSnippet:
      "Collapse a finished range of messages into one summary via their [#id] markers",
    promptGuidelines: [
      "Use forget_range to replace a finished span of the conversation (from..to by their [#id] markers) with one short summary you write; recall_messages restores all originals at once.",
      "Whenever you finish a task or a self-contained sub-thread, routinely collapse its messages into a single summary with forget_range to keep the working context lean. Capture decisions, outcomes and anything still needed later in the summary.",
    ],
    parameters: FromToParam,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const msgs = branchMessages(ctx);
      const indexById = new Map(msgs.map((m, i) => [m.id, i] as const));
      const spanByFrom = new Map(spans.map((s) => [s.fromId, s] as const));
      const startIdx = (id: string) => {
        const s = spanByFrom.get(id);
        return indexById.get(s ? s.memberIds[0] : id);
      };
      const endIdx = (id: string) => {
        const s = spanByFrom.get(id);
        return indexById.get(s ? s.memberIds[s.memberIds.length - 1] : id);
      };
      const a = startIdx(params.from);
      const b = endIdx(params.to);
      const unknown = [
        ...(a === undefined ? [params.from] : []),
        ...(b === undefined ? [params.to] : []),
      ];
      if (unknown.length) {
        return {
          content: [
            { type: "text", text: `unknown id(s): ${unknown.join(", ")}` },
          ],
          details: {
            action: "forget",
            applied: [],
            unknown,
            noop: [],
            total: pruned.size + spans.length,
          } as PruneDetails,
        };
      }
      const reqLo = Math.min(a!, b!);
      const reqHi = Math.max(a!, b!);
      const bounds = unitBounds(msgs);
      const { lo, hi } = expandRange(msgs, bounds, spans, reqLo, reqHi);
      const memberIds = msgs.slice(lo, hi + 1).map((m) => m.id);
      const memberSet = new Set(memberIds);
      // Absorbierte Spans entfernen (flach) und Einzel-Tombstones im Bereich aufloesen.
      for (let i = spans.length - 1; i >= 0; i--) {
        if (spans[i].memberIds.some((id) => memberSet.has(id)))
          spans.splice(i, 1);
      }
      for (const id of memberIds) pruned.delete(id);
      spans.push({ fromId: memberIds[0], memberIds, summary: params.summary });
      persist();
      const snapped = lo < reqLo || hi > reqHi;
      const text =
        `Collapsed ${memberIds.length} message(s) into a summary [#${memberIds[0]}]` +
        (snapped ? " (range snapped outward to keep tool pairs whole)" : "") +
        ".";
      return {
        content: [{ type: "text", text }],
        details: {
          action: "forget",
          applied: [memberIds[0]],
          unknown: [],
          noop: [],
          total: pruned.size + spans.length,
        } as PruneDetails,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as PruneDetails | undefined;
      if (!d) return new Text("", 0, 0);
      if (!d.applied.length)
        return new Text(theme.fg("warning", `unknown id(s)`), 0, 0);
      return new Text(
        theme.fg("success", `✓ summarized → ${d.applied[0]}`),
        0,
        0,
      );
    },
  });
}
