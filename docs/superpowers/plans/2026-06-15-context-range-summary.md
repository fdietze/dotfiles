# Context Range Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `forget_range` tool to the `context-prune` pi extension that collapses a contiguous range of messages into one agent-written summary message, reversibly.

**Architecture:** Extends the existing single-file extension. New in-memory `spans` state (alongside `pruned`) is persisted in the same `context-prune` custom session entry. The `context` event handler renders spans by replacing the first member with a synthetic `user` summary message and omitting the rest; range resolution snaps outward to keep tool call/result units whole and flatly absorbs overlapping spans.

**Tech Stack:** TypeScript pi extension, `@earendil-works/pi-coding-agent` API, `typebox` for tool schemas, `@earendil-works/pi-tui` for result rendering.

**Spec:** `docs/superpowers/specs/2026-06-15-context-range-summary-design.md`

---

## File Structure

Only one file changes — the extension is self-contained:

- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`
  - new `Span` type and module-level pure helpers (`branchMessages`, `unitBounds`, `expandRange`)
  - extended `spans` state + persistence/reconstruct
  - new `forget_range` tool
  - extended `context` handler and `recall_messages` tool

No nix change: `pi-extensions.nix` auto-links every top-level `*.ts`.

## Testing approach

This extension is coupled to the pi runtime (`ExtensionAPI`, `SessionManager`, the `context` event). The repo has no TS toolchain or test runner for pi extensions, so per the spec there are no automated unit tests. The per-task automated gate is a syntax/type-strip parse check:

```bash
node --experimental-strip-types --check modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts
```

Expected: exits 0 with no output. (This validates parse + type-stripping; it does NOT type-check against pi types.) Real behaviour is verified manually in a live pi session in the final task.

---

## Task 1: Span state + persistence

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`

- [ ] **Step 1: Add the `Span` type after `PruneDetails`**

Insert this interface immediately after the closing `}` of the `PruneDetails` interface:

```ts
// Eine zusammengefasste Range: ihre Summary-Message erbt fromId (= erstes
// Member) als sichtbare id, damit sie selbst wieder in eine Range aufgenommen
// und per recall aufgeloest werden kann. memberIds sind immer echte Entry-ids
// (flach), zusammenhaengend und in Branch-Reihenfolge aufsteigend.
interface Span {
	fromId: string;
	memberIds: string[];
	summary: string;
}
```

- [ ] **Step 2: Add the `spans` state next to `pruned`**

Find:

```ts
	// In-memory Quelle der Wahrheit, aus der Session rekonstruiert.
	const pruned = new Set<string>();
```

Replace with:

```ts
	// In-memory Quelle der Wahrheit, aus der Session rekonstruiert.
	const pruned = new Set<string>();
	const spans: Span[] = [];
```

- [ ] **Step 3: Update `reconstruct` to read both pruned and spans**

Find the whole `reconstruct` arrow function:

```ts
	const reconstruct = (ctx: ExtensionContext) => {
		pruned.clear();
		// Letzter Custom-Entry auf dem Branch gewinnt (kumulativer Snapshot).
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === PRUNE_ENTRY) {
				const ids = (entry.data as { pruned?: string[] } | undefined)?.pruned ?? [];
				pruned.clear();
				for (const id of ids) pruned.add(id);
			}
		}
	};
	const persist = () => pi.appendEntry(PRUNE_ENTRY, { pruned: [...pruned] });
```

Replace with:

```ts
	const reconstruct = (ctx: ExtensionContext) => {
		pruned.clear();
		spans.length = 0;
		// Letzter Custom-Entry auf dem Branch gewinnt (kumulativer Snapshot).
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === PRUNE_ENTRY) {
				const data = entry.data as { pruned?: string[]; spans?: Span[] } | undefined;
				pruned.clear();
				spans.length = 0;
				for (const id of data?.pruned ?? []) pruned.add(id);
				for (const s of data?.spans ?? []) spans.push(s);
			}
		}
	};
	const persist = () => pi.appendEntry(PRUNE_ENTRY, { pruned: [...pruned], spans });
```

- [ ] **Step 4: Syntax check**

Run: `node --experimental-strip-types --check modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`
Expected: exits 0, no output.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts
git commit -m "pi(context-prune): add span state and persistence for range summaries"
```

---

## Task 2: Range-resolution helpers

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`

These are pure module-level functions (no closure state) used by both the tool and the context handler.

- [ ] **Step 1: Add the helpers after the `tombstone` function**

Insert immediately after the closing `}` of `function tombstone(...)` and before `export default function (pi: ExtensionAPI) {`:

```ts
/** Geordnete, taggbare Message-Entries des aktuellen Branch (Branch-Reihenfolge). */
function branchMessages(ctx: ExtensionContext): { id: string; message: AgentMessageLike }[] {
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
function unitBounds(msgs: { id: string; message: AgentMessageLike }[]): { start: number[]; end: number[] } {
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
			if (a !== undefined) (resultsByOwner.get(a) ?? resultsByOwner.set(a, []).get(a)!).push(i);
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
```

- [ ] **Step 2: Syntax check**

Run: `node --experimental-strip-types --check modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`
Expected: exits 0, no output. (`branchMessages`/`unitBounds`/`expandRange` are unused for now — that is fine; type-strip does not error on unused functions.)

- [ ] **Step 3: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts
git commit -m "pi(context-prune): add range-resolution helpers (units, snapping, absorption)"
```

---

## Task 3: `forget_range` tool

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`

- [ ] **Step 1: Register the tool after the `recall_messages` tool**

Insert this block immediately after the closing `});` of the `recall_messages` `pi.registerTool({ ... })` call, before the final `}` that closes `export default function`:

```ts
	const FromToParam = Type.Object({
		from: Type.String({
			description: "Start id (the 8-char hex in a [#id] marker); a real message or an existing summary's id.",
		}),
		to: Type.String({
			description: "End id (the 8-char hex in a [#id] marker), inclusive. Order relative to `from` does not matter.",
		}),
		summary: Type.String({ description: "Short summary text that replaces the whole range." }),
	});

	pi.registerTool({
		name: "forget_range",
		label: "Forget Range",
		description:
			"Collapse a contiguous range of messages (from..to, inclusive, by their [#id] markers) into a single " +
			"summary you write. Reclaims context on finished sub-threads. The range snaps outward to keep tool " +
			"call/result pairs whole. Reversible via recall_messages.",
		promptSnippet: "Collapse a finished range of messages into one summary via their [#id] markers",
		promptGuidelines: [
			"Use forget_range to replace a finished span of the conversation (from..to by their [#id] markers) with one short summary you write; recall_messages restores all originals at once.",
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
			const unknown = [...(a === undefined ? [params.from] : []), ...(b === undefined ? [params.to] : [])];
			if (unknown.length) {
				return {
					content: [{ type: "text", text: `unknown id(s): ${unknown.join(", ")}` }],
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
				if (spans[i].memberIds.some((id) => memberSet.has(id))) spans.splice(i, 1);
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
			if (!d.applied.length) return new Text(theme.fg("warning", `unknown id(s)`), 0, 0);
			return new Text(theme.fg("success", `✓ summarized → ${d.applied[0]}`), 0, 0);
		},
	});
```

- [ ] **Step 2: Syntax check**

Run: `node --experimental-strip-types --check modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`
Expected: exits 0, no output.

- [ ] **Step 3: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts
git commit -m "pi(context-prune): add forget_range tool to collapse a range into one summary"
```

---

## Task 4: Render spans in the context handler

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`

- [ ] **Step 1: Replace the per-message loop and return in the `context` handler**

Find:

```ts
		for (const message of event.messages as AgentMessageLike[]) {
			if (!TAGGABLE_ROLES.has(message.role)) continue;
			const id = idQueues.get(`${message.timestamp}|${message.role}`)?.shift();
			if (!id) continue;
			if (pruned.has(id)) tombstone(message, id);
			else tag(message, id);
		}
		return { messages: event.messages };
	});
```

Replace with:

```ts
		// Span-Lookups: fromId -> Span (durch Summary ersetzen), uebrige Member weglassen.
		const spanByFrom = new Map(spans.map((s) => [s.fromId, s] as const));
		const hiddenMembers = new Set<string>();
		for (const s of spans) for (const id of s.memberIds.slice(1)) hiddenMembers.add(id);

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
```

- [ ] **Step 2: Syntax check**

Run: `node --experimental-strip-types --check modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`
Expected: exits 0, no output.

- [ ] **Step 3: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts
git commit -m "pi(context-prune): render spans as one summary message in context event"
```

---

## Task 5: Dissolve spans on recall + unify counts

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`

- [ ] **Step 1: Extend `recall_messages` to also dissolve spans**

Find the `recall_messages` `execute` body:

```ts
		async execute(_id, params, _signal, _onUpdate, _ctx) {
			const applied: string[] = [];
			const noop: string[] = [];
			for (const id of params.ids) {
				if (pruned.delete(id)) applied.push(id);
				else noop.push(id);
			}
			if (applied.length) persist();
			return {
				content: [{ type: "text", text: summarize("recall", applied, [], noop) }],
				details: { action: "recall", applied, unknown: [], noop, total: pruned.size } as PruneDetails,
			};
		},
```

Replace with:

```ts
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
				content: [{ type: "text", text: summarize("recall", applied, [], noop) }],
				details: {
					action: "recall",
					applied,
					unknown: [],
					noop,
					total: pruned.size + spans.length,
				} as PruneDetails,
			};
		},
```

- [ ] **Step 2: Make `forget_messages` count spans in `total` too**

Find (in the `forget_messages` tool):

```ts
				details: { action: "forget", applied, unknown, noop, total: pruned.size } as PruneDetails,
```

Replace with:

```ts
				details: { action: "forget", applied, unknown, noop, total: pruned.size + spans.length } as PruneDetails,
```

- [ ] **Step 3: Syntax check**

Run: `node --experimental-strip-types --check modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts`
Expected: exits 0, no output.

- [ ] **Step 4: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts
git commit -m "pi(context-prune): dissolve spans on recall and count them in totals"
```

---

## Task 6: Manual verification in a live pi session

**Files:** none (verification only).

This task cannot be automated; it requires the pi runtime after the extension is symlinked.

- [ ] **Step 1: Activate the extension**

The user runs the home-manager switch manually (never run `nrs`/activation yourself). After it completes, in pi run `/reload` to pick up the new extension code.

- [ ] **Step 2: Verify collapse across a tool call/result**

Trigger a tool call (e.g. a `Read`), note the `[#id]` of the assistant tool-call message and its tool result, then call `forget_range({ from, to, summary })` covering them. Expected: result says `Collapsed N message(s) into a summary [#...]`, and on the next turn the range shows as a single `[#id] (summary) ...` user message with no provider error.

- [ ] **Step 3: Verify outward snapping**

Call `forget_range` with `from`/`to` that land strictly inside a tool unit (e.g. only the tool result, not its call). Expected: result mentions "range snapped outward to keep tool pairs whole" and the summary still collapses cleanly.

- [ ] **Step 4: Verify flat re-summary**

Call `forget_range` again with a range that includes an existing summary's `[#id]` plus neighbouring messages. Expected: the old summary is absorbed; one new summary replaces the union.

- [ ] **Step 5: Verify recall**

Call `recall_messages({ ids: ["<summary id>"] })`. Expected: result says `Recalled 1 message(s)` and on the next turn all original messages reappear, each re-tagged with its `[#id]`.

- [ ] **Step 6: Verify persistence**

Run `/reload` again and confirm any still-active summary remains collapsed (state reconstructed from the session entry).
