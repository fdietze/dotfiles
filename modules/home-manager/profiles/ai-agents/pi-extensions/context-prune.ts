/**
 * Context Prune - der Agent bearbeitet seinen eigenen Kontext.
 *
 * Idee: Jede Conversation-Message bekommt im `context`-Event (nur fuer den
 * jeweiligen LLM-Call, non-destruktiv) einen sichtbaren `[#id]`-Marker
 * vorangestellt. Der Agent referenziert damit Messages und ruft `forget`
 * (Range vergessen, optional mit Summary) bzw. `remember` (wiederherstellen).
 *
 * Warum Marker im Text statt im JSON: Der Provider serialisiert nur `role` +
 * `content`; Zusatzfelder am Message-Objekt erreichen das Modell nie. Die
 * Entry-`id` lebt zudem nur am Session-*Entry* (getBranch()), nicht an der
 * AgentMessage (siehe docs/session-format.md). Deshalb wird im context-Handler
 * Entry<->Message ueber `timestamp`+`role` korreliert (gemeinsamer, 1:1
 * kopierter Schluessel), dann der Marker in den ersten Text-Block gepatcht.
 *
 * EIN Mechanismus: Jedes Vergessen ist eine `Span` (eine auf ganze Tool-
 * Einheiten gesnappte Range) mit optionaler Summary. Eine Span mit einem
 * Member und leerer Summary ist das fruehere "Tombstone" (Content weg, Stub
 * bleibt). Da Spans immer ganze toolCall/toolResult-Einheiten umfassen
 * (expandRange), kann das Ersetzen durch EINE synthetische user-Message nie ein
 * Paar verwaisen lassen - es braucht keine Sonderbehandlung pro Rolle. Alles
 * ist voll reversibel (remember).
 *
 * Persistenz: Die kumulative Span-Liste wird via pi.appendEntry als Custom-
 * Entry in die Session geschrieben und in session_start/session_tree wieder
 * rekonstruiert (analog examples/extensions/todo.ts) -> ueberlebt /reload und
 * folgt korrekt der Branch-History. Alt-Sessions mit `pruned`-Liste werden
 * beim Lesen in Single-Member-Spans migriert.
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

// Custom-Entry-Typ fuer die persistierte Span-Liste.
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
  action: "forget" | "remember";
  applied: string[]; // forget: fromIds der neuen Spans; remember: aufgeloeste ids
  unknown: string[];
  noop: string[];
  collapsed: number; // forget: Anzahl zusammengefasster Messages
  summaries: string[]; // forget: Summary pro applied-Span ("" = reines Droppen)
  total: number; // spans.length
}

// Eine vergessene Range: ihre Stub-Message erbt fromId (= erstes Member) als
// sichtbare id, damit sie selbst wieder in eine Range aufgenommen und per
// remember aufgeloest werden kann. memberIds sind immer echte Entry-ids (flach),
// zusammenhaengend und in Branch-Reihenfolge aufsteigend. summary == "" -> die
// Range wird nur gedroppt (Stub "(forgotten N)"), sonst durch die Summary ersetzt.
interface Span {
  fromId: string;
  memberIds: string[];
  summary: string;
}

// Marker, den der Agent liest und an forget/remember zurueckgibt.
const marker = (id: string) => `[#${id}]`;

// Fuehrende [#8hex]-Marker, die das Modell in der eigenen Ausgabe imitiert.
// Prompt-Anweisungen verhindern das nicht: empirisch ~85% Imitation ueber
// haiku-4-5 und sonnet-4-5 (3 Prompt-Varianten getestet, inkl. Few-Shot),
// weil First-Token-Pattern-Continuation Instruktionen schlaegt; zudem
// akkumuliert es (bis ~30 Marker/Message). Daher am Ausgabe-Rand (message_end)
// herausfiltern -> Fakes werden nie persistiert und koennen nicht akkumulieren.
// Nur fuehrend/positional: eine id, die mitten im Prosatext referenziert wird
// (z.B. "forgetting [#abc12345]"), bleibt erhalten.
const LEADING_FAKE_MARKERS = /^(?:\s*\[#[0-9a-f]{8}\]\s*)+/;
function stripLeadingMarkers(message: AgentMessageLike): AgentMessageLike {
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

/** Sichtbaren `[#id]`-Marker an den ersten Text-Block voranstellen. */
function tag(message: AgentMessageLike, id: string): void {
  const prefix = `${marker(id)} `;
  // Bereits persistierte Fakes aus Alt-Sessions beim Taggen mit-entfernen
  // (message_end greift nur fuer neue Messages). Nur fuer assistant, da nur das
  // Modell Marker imitiert; user/toolResult-Text bleibt unangetastet.
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
  // Kein Text-Block (z.B. Assistant nur mit toolCall): nach fuehrenden
  // thinking-Bloecken einfuegen, damit die Provider-Reihenfolge stimmt.
  let insertAt = 0;
  while (insertAt < blocks.length && blocks[insertAt]?.type === "thinking")
    insertAt++;
  blocks.splice(insertAt, 0, { type: "text", text: marker(id) });
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
  const spans: Span[] = [];

  const reconstruct = (ctx: ExtensionContext) => {
    spans.length = 0;
    // Letzter Custom-Entry auf dem Branch gewinnt (kumulativer Snapshot).
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type === "custom" && entry.customType === PRUNE_ENTRY) {
        const data = entry.data as
          | { pruned?: string[]; spans?: Span[] }
          | undefined;
        spans.length = 0;
        for (const s of data?.spans ?? []) spans.push(s);
        // Alt-Sessions: jedes `pruned`-Tombstone -> Single-Member-Span ohne Summary.
        for (const id of data?.pruned ?? [])
          spans.push({ fromId: id, memberIds: [id], summary: "" });
      }
    }
  };
  const persist = () => pi.appendEntry(PRUNE_ENTRY, { spans });

  pi.on("session_start", async (_event, ctx) => reconstruct(ctx));
  pi.on("session_tree", async (_event, ctx) => reconstruct(ctx));

  // Imitierte fuehrende Marker aus der finalisierten Assistant-Message
  // entfernen, bevor sie gespeichert/angezeigt wird (siehe stripLeadingMarkers).
  // Das ist die eigentliche Loesung gegen Imitation+Akkumulation; der Prompt
  // allein wirkt nicht (s.o.).
  pi.on("message_end", async (event) => {
    if (event.message.role !== "assistant") return;
    const original = event.message as AgentMessageLike;
    const m = stripLeadingMarkers(original);
    if (m === original) return;
    return { message: m };
  });

  // Marker injizieren bzw. vergessene Ranges durch einen Stub ersetzen - jedes
  // Mal deterministisch, damit das Prompt-Caching stabil bleibt.
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

    // Span-Lookups: fromId -> Span (durch Stub ersetzen), uebrige Member weglassen.
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
        // Ganze Range durch EINE synthetische user-Message ersetzen. Da der Span
        // immer ganze Tool-Einheiten umfasst, koennen die weggelassenen Member
        // nie ein toolCall/toolResult-Paar verwaisen lassen.
        const n = span.memberIds.length;
        message.role = "user";
        message.content = span.summary
          ? `${marker(id)} (summary) ${span.summary}`
          : `${marker(id)} (forgotten ${n} message${n > 1 ? "s" : ""})`;
        message.details = undefined;
        message.toolCallId = undefined;
        out.push(message);
        continue;
      }
      tag(message, id);
      out.push(message);
    }
    return { messages: out };
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
              "Optional one-line digest that replaces the range. Omit to just drop the content (noise).",
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
      "[#id] markers; each is { from, to?, summary? }. With `summary`, the range collapses into your one-line " +
      "digest (use for finished sub-threads worth condensing). Without `summary`, the range's content is just " +
      "dropped (use for noise: tool outputs, detours, resolved debugging). `to` defaults to `from` for a single " +
      "message. Ranges snap outward to keep tool call/result pairs whole. Restore later with remember.",
    promptSnippet:
      "Forget/compact earlier messages via their [#id] markers to free context",
    promptGuidelines: [
      "`[#id]` markers are labels the system prepends to each message so you can reference it — they are NOT part of the message text. Never write a `[#id]` marker in your own replies. Use these ids only as arguments to `forget` / `remember`.",
      "Routinely forget finished sub-threads: pass a range with a short `summary` to condense it, or without `summary` to drop pure noise (tool outputs, detours, resolved debugging). Keeps the working context lean; reversible via `remember`.",
    ],
    parameters: ForgetParam,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const msgs = branchMessages(ctx);
      const indexById = new Map(msgs.map((m, i) => [m.id, i] as const));
      const bounds = unitBounds(msgs);
      const applied: string[] = [];
      const summaries: string[] = [];
      const unknown: string[] = [];
      let collapsed = 0;
      for (const item of params.items) {
        // Spans mutieren pro Item -> Lookup jeweils frisch.
        const spanByFrom = new Map(spans.map((s) => [s.fromId, s] as const));
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
          spans,
          Math.min(a, b),
          Math.max(a, b),
        );
        const memberIds = msgs.slice(lo, hi + 1).map((m) => m.id);
        const memberSet = new Set(memberIds);
        // Ueberlappte Spans flach absorbieren (deren Member sind voll enthalten).
        for (let i = spans.length - 1; i >= 0; i--) {
          if (spans[i].memberIds.some((id) => memberSet.has(id)))
            spans.splice(i, 1);
        }
        spans.push({
          fromId: memberIds[0],
          memberIds,
          summary: item.summary ?? "",
        });
        applied.push(memberIds[0]);
        summaries.push(item.summary ?? "");
        collapsed += memberIds.length;
      }
      if (applied.length) persist();
      const text = applied.length
        ? `Forgot ${collapsed} message(s) into ${applied.length} stub(s): ${applied.join(", ")}` +
          (unknown.length ? `. unknown id(s): ${unknown.join(", ")}` : "")
        : `Forgot nothing. unknown id(s): ${unknown.join(", ")}`;
      return {
        content: [{ type: "text", text }],
        details: {
          action: "forget",
          applied,
          unknown,
          noop: [],
          collapsed,
          summaries,
          total: spans.length,
        } as PruneDetails,
      };
    },
    renderResult(result, _opts, theme) {
      const d = result.details as PruneDetails | undefined;
      if (!d) return new Text("", 0, 0);
      if (!d.applied.length)
        return new Text(theme.fg("warning", "unknown id(s)"), 0, 0);
      const sum = d.summaries.find((s) => s);
      const tail = sum
        ? ` → ${sum.length > 80 ? sum.slice(0, 79) + "…" : sum}`
        : "";
      return new Text(
        theme.fg("success", `✓ forgot ${d.collapsed} msg(s)`) +
          theme.fg("dim", `${tail} (${d.total} total)`),
        0,
        0,
      );
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
      const applied: string[] = [];
      const noop: string[] = [];
      for (const id of params.ids) {
        const i = spans.findIndex((s) => s.fromId === id);
        if (i >= 0) {
          spans.splice(i, 1);
          applied.push(id);
        } else {
          noop.push(id);
        }
      }
      if (applied.length) persist();
      const text =
        (applied.length
          ? `Remembered ${applied.length}: ${applied.join(", ")}`
          : "Remembered nothing") +
        (noop.length ? `. not forgotten: ${noop.join(", ")}` : "");
      return {
        content: [{ type: "text", text }],
        details: {
          action: "remember",
          applied,
          unknown: [],
          noop,
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
