# Question extension: always multi-select + text wrapping — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the pi `question` tool from single-select+truncate to always-multi-select checkboxes with a combinable custom-note field, wrapping all text to terminal width.

**Architecture:** Functional Core / Imperative Shell. Split the single `question.ts` into a `question/` extension dir: `core.ts` (pure result-formatting + cursor logic, unit-tested with `node:test`), `index.ts` (TUI shell wiring the `Editor`, checkboxes, keys, and `wrapTextWithAnsi` rendering). The nix loader (`pi-extensions.nix`) auto-discovers `question/index.ts`.

**Tech Stack:** TypeScript, `@earendil-works/pi-coding-agent` (ExtensionAPI), `@earendil-works/pi-tui` (Editor, Key, matchesKey, wrapTextWithAnsi, truncateToWidth, Text), typebox. Tests via `node --test --experimental-strip-types`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-24-question-multiselect-wrap-design.md`.
- Tool params UNCHANGED: `question: string`, `options: [{label: string, description?: string}]`. No new agent-facing params.
- Multi-select always on; custom note always present. No `multiple` flag. (KISS/YAGNI)
- Empty submit (nothing checked, empty note) = valid deliberate answer, `cancelled: false`. Cancel is exclusively `Esc` from nav.
- Tests use `node:test` + `node:assert/strict`, run with `node --test --experimental-strip-types <file>` (matches existing `context-prune/core.test.ts`, `subagents/*.test.ts`).
- Comments document why per AGENTS.md; comments refer to current code only.
- User runs the home-manager switch (`nrs`) manually — never run it. `nixos-rebuild build` is fine for verification but not needed here.

## File Structure

- `modules/home-manager/profiles/ai-agents/pi-extensions/question/core.ts` — pure logic (NEW)
- `modules/home-manager/profiles/ai-agents/pi-extensions/question/core.test.ts` — node:test (NEW)
- `modules/home-manager/profiles/ai-agents/pi-extensions/question/index.ts` — TUI shell (NEW, replaces old file)
- `modules/home-manager/profiles/ai-agents/pi-extensions/question.ts` — DELETE (becomes `question/index.ts`)
- `hosts-nixos/gurke/home.nix:19` — devLink path `.../question.ts` → `.../question` (MODIFY)

The loader links top-level `*.ts` AND subdirs containing `index.ts`. Renaming `question.ts` → `question/index.ts` keeps it discovered as the `question` extension.

---

### Task 1: Pure core — result formatting + cursor logic

**Files:**
- Create: `modules/home-manager/profiles/ai-agents/pi-extensions/question/core.ts`
- Test: `modules/home-manager/profiles/ai-agents/pi-extensions/question/core.test.ts`

**Interfaces:**
- Consumes: nothing (leaf module).
- Produces:
  - `interface ResultModel { selected: string[]; note: string | null; content: string; isEmpty: boolean }`
  - `formatResult(labels: string[], checked: boolean[], noteText: string): ResultModel`
  - `clampCursor(cursor: number, optionCount: number): number` — valid rows are `0..optionCount` inclusive; row `optionCount` is the note row.
  - `isNoteRow(cursor: number, optionCount: number): boolean`

`formatResult` rules (numbering uses ORIGINAL 1-based option index):
- `selected` = labels where `checked[i]` true, in order.
- `note` = `noteText.trim()` or `null` if empty after trim.
- `selStr` = selected labels each prefixed `${origIndex+1}. `, joined `", "`.
- `content`:
  - both selected & note: `User selected: ${selStr} | note: ${note}`
  - selected only: `User selected: ${selStr}`
  - note only: `User note: ${note}`
  - neither: `User submitted empty answer (no options, no note)`
- `isEmpty` = `selected.length === 0 && note === null`.

- [ ] **Step 1: Write the failing tests**

```ts
// modules/home-manager/profiles/ai-agents/pi-extensions/question/core.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { formatResult, clampCursor, isNoteRow } from "./core.ts";

test("formatResult: selected + note uses original 1-based indices and joins both sides", () => {
	const r = formatResult(["A", "B", "C"], [false, true, true], "  hi  ");
	assert.deepEqual(r.selected, ["B", "C"]);
	assert.equal(r.note, "hi"); // trimmed
	assert.equal(r.content, "User selected: 2. B, 3. C | note: hi");
	assert.equal(r.isEmpty, false);
});

test("formatResult: selected only omits note side", () => {
	const r = formatResult(["A", "B"], [true, false], "   ");
	assert.deepEqual(r.selected, ["A"]);
	assert.equal(r.note, null);
	assert.equal(r.content, "User selected: 1. A");
	assert.equal(r.isEmpty, false);
});

test("formatResult: note only", () => {
	const r = formatResult(["A", "B"], [false, false], "ship it");
	assert.deepEqual(r.selected, []);
	assert.equal(r.note, "ship it");
	assert.equal(r.content, "User note: ship it");
	assert.equal(r.isEmpty, false);
});

test("formatResult: empty submit is valid, not cancel", () => {
	const r = formatResult(["A"], [false], "");
	assert.equal(r.content, "User submitted empty answer (no options, no note)");
	assert.equal(r.isEmpty, true);
	assert.equal(r.note, null);
});

test("formatResult: works with zero options (note-only path)", () => {
	const r = formatResult([], [], "just a note");
	assert.equal(r.content, "User note: just a note");
	assert.deepEqual(r.selected, []);
});

test("clampCursor: valid rows are 0..optionCount inclusive (note row = optionCount)", () => {
	assert.equal(clampCursor(-1, 3), 0);
	assert.equal(clampCursor(5, 3), 3); // note row
	assert.equal(clampCursor(2, 3), 2);
});

test("isNoteRow: true only at index optionCount", () => {
	assert.equal(isNoteRow(3, 3), true);
	assert.equal(isNoteRow(2, 3), false);
	assert.equal(isNoteRow(0, 0), true); // no options: row 0 is the note row
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd modules/home-manager/profiles/ai-agents/pi-extensions/question && node --test --experimental-strip-types core.test.ts`
Expected: FAIL — `Cannot find module './core.ts'` (or export not found).

- [ ] **Step 3: Write minimal implementation**

```ts
// modules/home-manager/profiles/ai-agents/pi-extensions/question/core.ts
// Pure logic for the question tool: result formatting + cursor bounds.
// Functional core — no TUI/IO — so it is unit-testable with node:test.

export interface ResultModel {
	selected: string[]; // checked option labels, in original order
	note: string | null; // trimmed custom note, null if empty
	content: string; // text the agent reads
	isEmpty: boolean; // nothing checked and no note (still a valid submit)
}

// Build the agent-facing result. Numbering uses the ORIGINAL 1-based option
// index so the agent can map an answer back to the option it offered.
export function formatResult(labels: string[], checked: boolean[], noteText: string): ResultModel {
	const selected: string[] = [];
	const selParts: string[] = [];
	for (let i = 0; i < labels.length; i++) {
		if (checked[i]) {
			selected.push(labels[i]);
			selParts.push(`${i + 1}. ${labels[i]}`);
		}
	}
	const trimmed = noteText.trim();
	const note = trimmed.length > 0 ? trimmed : null;
	const selStr = selParts.join(", ");

	let content: string;
	if (selected.length > 0 && note !== null) {
		content = `User selected: ${selStr} | note: ${note}`;
	} else if (selected.length > 0) {
		content = `User selected: ${selStr}`;
	} else if (note !== null) {
		content = `User note: ${note}`;
	} else {
		content = "User submitted empty answer (no options, no note)";
	}

	return { selected, note, content, isEmpty: selected.length === 0 && note === null };
}

// Rows are: option rows 0..optionCount-1, then the note row at index optionCount.
export function clampCursor(cursor: number, optionCount: number): number {
	if (cursor < 0) return 0;
	if (cursor > optionCount) return optionCount;
	return cursor;
}

export function isNoteRow(cursor: number, optionCount: number): boolean {
	return cursor === optionCount;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd modules/home-manager/profiles/ai-agents/pi-extensions/question && node --test --experimental-strip-types core.test.ts`
Expected: PASS — `tests 7  pass 7  fail 0`.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/question/core.ts modules/home-manager/profiles/ai-agents/pi-extensions/question/core.test.ts
git commit -m "question: add pure core (formatResult, cursor bounds) + tests"
```

---

### Task 2: TUI shell — multi-select checkboxes, custom note, wrapping

**Files:**
- Create: `modules/home-manager/profiles/ai-agents/pi-extensions/question/index.ts`
- Delete: `modules/home-manager/profiles/ai-agents/pi-extensions/question.ts`
- Modify: `hosts-nixos/gurke/home.nix:19`

**Interfaces:**
- Consumes from Task 1: `formatResult`, `clampCursor`, `isNoteRow`, `ResultModel` from `./core.ts`.
- Produces: default-exported `question(pi: ExtensionAPI)` extension (registers tool `question`).

**Behavior (from spec):**
- On open: cursor on note row (`= options.length`), `mode = "edit"`, Editor focused.
- `Enter` anywhere (incl. edit) → submit: read `editor.getText()`, build via `formatResult`, `done({...})`.
- `Esc` in edit → `mode = "nav"` (do NOT clear note); re-render.
- `Esc` in nav → cancel (`done(null)`).
- `↑/↓` in nav → `clampCursor(cursor ± 1, options.length)`.
- `Space` in nav on an option row → toggle `checked[cursor]`.
- `Space` or any printable key in nav on the note row → `mode = "edit"` (printable key is then forwarded to editor).
- Render with `wrapTextWithAnsi` for question, labels, descriptions; reapply theme style per wrapped line. Separator = `"─".repeat(width)` (accent), kept full-width.

- [ ] **Step 1: Move the old file into the new dir as the starting point**

```bash
cd modules/home-manager/profiles/ai-agents/pi-extensions
git mv question.ts question/index.ts
```

(Preserves history; `question/core.ts` already exists from Task 1.)

- [ ] **Step 2: Rewrite `question/index.ts`**

Replace the ENTIRE contents of `question/index.ts` with:

```ts
/**
 * Question Tool — always multi-select checkboxes + combinable custom note.
 * Full custom UI. Note field is focused (edit mode) on open. Enter submits the
 * whole set from anywhere; Esc in edit returns to navigation; Esc in navigation
 * cancels. All text wraps to terminal width (wrapTextWithAnsi).
 * Pure result/cursor logic lives in ./core.ts (unit-tested).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	Editor,
	type EditorTheme,
	Key,
	matchesKey,
	Text,
	truncateToWidth,
	wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { clampCursor, formatResult, isNoteRow } from "./core.ts";

interface OptionWithDesc {
	label: string;
	description?: string;
}

interface QuestionDetails {
	question: string;
	options: string[]; // all offered labels
	selected: string[]; // checked labels
	note: string | null;
	cancelled: boolean;
}

const OptionSchema = Type.Object({
	label: Type.String({ description: "Display label for the option" }),
	description: Type.Optional(Type.String({ description: "Optional description shown below label" })),
});

const QuestionParams = Type.Object({
	question: Type.String({ description: "The question to ask the user" }),
	options: Type.Array(OptionSchema, { description: "Options for the user to choose from" }),
});

export default function question(pi: ExtensionAPI) {
	pi.registerTool({
		name: "question",
		label: "Question",
		description:
			"Ask the user a question. They pick any number of the given options (checkboxes) and/or write a custom note. Use when you need user input to proceed.",
		parameters: QuestionParams,

		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const labels = params.options.map((o) => o.label);

			if (ctx.mode !== "tui") {
				return {
					content: [{ type: "text", text: "Error: UI not available (running in non-interactive mode)" }],
					details: {
						question: params.question,
						options: labels,
						selected: [],
						note: null,
						cancelled: true,
					} as QuestionDetails,
				};
			}

			const result = await ctx.ui.custom<{ selected: string[]; note: string | null; content: string } | null>(
				(tui, theme, _kb, done) => {
					const checked: boolean[] = params.options.map(() => false);
					// Note row sits after all option rows. Focused + editable on open.
					let cursor = params.options.length;
					let mode: "edit" | "nav" = "edit";
					let cachedLines: string[] | undefined;

					const editorTheme: EditorTheme = {
						borderColor: (s) => theme.fg("accent", s),
						selectList: {
							selectedPrefix: (t) => theme.fg("accent", t),
							selectedText: (t) => theme.fg("accent", t),
							description: (t) => theme.fg("muted", t),
							scrollInfo: (t) => theme.fg("dim", t),
							noMatch: (t) => theme.fg("warning", t),
						},
					};
					const editor = new Editor(tui, editorTheme);

					function refresh() {
						cachedLines = undefined;
						tui.requestRender();
					}

					function submit() {
						const r = formatResult(labels, checked, editor.getText());
						done({ selected: r.selected, note: r.note, content: r.content });
					}

					function handleInput(data: string) {
						// Enter submits the whole set from anywhere, including edit mode.
						if (matchesKey(data, Key.enter)) {
							submit();
							return;
						}

						if (mode === "edit") {
							if (matchesKey(data, Key.escape)) {
								mode = "nav";
								refresh();
								return;
							}
							editor.handleInput(data);
							refresh();
							return;
						}

						// nav mode
						if (matchesKey(data, Key.escape)) {
							done(null);
							return;
						}
						if (matchesKey(data, Key.up)) {
							cursor = clampCursor(cursor - 1, params.options.length);
							refresh();
							return;
						}
						if (matchesKey(data, Key.down)) {
							cursor = clampCursor(cursor + 1, params.options.length);
							refresh();
							return;
						}
						if (isNoteRow(cursor, params.options.length)) {
							// Space or any printable char enters edit; forward printables to editor.
							if (matchesKey(data, Key.space)) {
								mode = "edit";
								refresh();
								return;
							}
							if (data.length === 1 && data >= " ") {
								mode = "edit";
								editor.handleInput(data);
								refresh();
								return;
							}
							return;
						}
						// option row: Space toggles its checkbox
						if (matchesKey(data, Key.space)) {
							checked[cursor] = !checked[cursor];
							refresh();
						}
					}

					function render(width: number): string[] {
						if (cachedLines) return cachedLines;
						const lines: string[] = [];
						// Wrap a styled block: wrap raw text, then reapply style per line
						// (tui resets SGR each line, so styles must be reapplied).
						const addWrapped = (raw: string, indent: string, style: (t: string) => string) => {
							for (const w of wrapTextWithAnsi(raw, Math.max(1, width - indent.length))) {
								lines.push(truncateToWidth(indent + style(w), width));
							}
						};

						lines.push(truncateToWidth(theme.fg("accent", "─".repeat(width)), width));
						addWrapped(params.question, " ", (t) => theme.fg("text", t));
						lines.push("");

						for (let i = 0; i < params.options.length; i++) {
							const opt = params.options[i];
							const onRow = mode === "nav" && cursor === i;
							const box = checked[i] ? "[x]" : "[ ]";
							const pointer = onRow ? theme.fg("accent", ">") : " ";
							const labelStyle = (t: string) =>
								onRow || checked[i] ? theme.fg("accent", t) : theme.fg("text", t);
							addWrapped(`${box} ${i + 1}. ${opt.label}`, `${onRow ? "" : " "}`, (t) =>
								`${pointer} ${labelStyle(t)}`,
							);
							if (opt.description) {
								addWrapped(opt.description, "       ", (t) => theme.fg("muted", t));
							}
						}

						lines.push("");
						const noteFocused = isNoteRow(cursor, params.options.length);
						const notePointer = mode === "nav" && noteFocused ? theme.fg("accent", "> ") : "  ";
						lines.push(truncateToWidth(notePointer + theme.fg("muted", "Note:") + (mode === "edit" ? theme.fg("accent", " ✎") : ""), width));
						for (const line of editor.render(width - 2)) {
							lines.push(truncateToWidth(` ${line}`, width));
						}

						lines.push("");
						const hint =
							mode === "edit"
								? " Enter submit • Esc to navigate options"
								: " ↑↓ move • Space toggle/edit note • Enter submit • Esc cancel";
						lines.push(truncateToWidth(theme.fg("dim", hint), width));
						lines.push(truncateToWidth(theme.fg("accent", "─".repeat(width)), width));

						cachedLines = lines;
						return lines;
					}

					return {
						render,
						invalidate: () => {
							cachedLines = undefined;
						},
						handleInput,
					};
				},
			);

			if (!result) {
				return {
					content: [{ type: "text", text: "User cancelled the selection" }],
					details: {
						question: params.question,
						options: labels,
						selected: [],
						note: null,
						cancelled: true,
					} as QuestionDetails,
				};
			}

			return {
				content: [{ type: "text", text: result.content }],
				details: {
					question: params.question,
					options: labels,
					selected: result.selected,
					note: result.note,
					cancelled: false,
				} as QuestionDetails,
			};
		},

		renderCall(args, theme, _context) {
			let text = theme.fg("toolTitle", theme.bold("question ")) + theme.fg("muted", args.question);
			const opts = Array.isArray(args.options) ? args.options : [];
			if (opts.length) {
				const numbered = opts.map((o: OptionWithDesc, i: number) => `${i + 1}. ${o.label}`);
				text += `\n${theme.fg("dim", `  Options: ${numbered.join(", ")} (+ custom note)`)}`;
			} else {
				text += `\n${theme.fg("dim", "  (custom note only)")}`;
			}
			return new Text(text, 0, 0);
		},

		renderResult(result, _options, theme, _context) {
			const details = result.details as QuestionDetails | undefined;
			if (!details) {
				const text = result.content[0];
				return new Text(text?.type === "text" ? text.text : "", 0, 0);
			}
			if (details.cancelled) {
				return new Text(theme.fg("warning", "Cancelled"), 0, 0);
			}
			const parts: string[] = [];
			if (details.selected.length) {
				const numbered = details.selected.map((label) => {
					const idx = details.options.indexOf(label) + 1;
					return idx > 0 ? `${idx}. ${label}` : label;
				});
				parts.push(numbered.join(", "));
			}
			if (details.note) parts.push(`note: ${details.note}`);
			const body = parts.length ? parts.join(" | ") : "(empty answer)";
			return new Text(theme.fg("success", "✓ ") + theme.fg("accent", body), 0, 0);
		},
	});
}
```

- [ ] **Step 3: Re-run core tests (shell must not break the dir's test run)**

Run: `cd modules/home-manager/profiles/ai-agents/pi-extensions/question && node --test --experimental-strip-types core.test.ts`
Expected: PASS — `tests 7  pass 7  fail 0`. (The shell `index.ts` imports `pi-tui` and cannot be imported standalone; it is verified by manual reload in Step 5.)

- [ ] **Step 4: Update the devLink path**

In `hosts-nixos/gurke/home.nix`, change the question devLink from the file to the dir:

```nix
    "modules/home-manager/profiles/ai-agents/pi-extensions/question"
```

(was `.../pi-extensions/question.ts`.)

- [ ] **Step 5: Commit, then user switches + verifies in pi**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/question/index.ts hosts-nixos/gurke/home.nix
git commit -m "question: always multi-select checkboxes + custom note + wrapping"
```

Then ask the USER to run their switch (`nrs`, manual) so `~/.pi/agent/extensions/question` links to the new dir, and in pi `/reload`, then trigger a `question` tool call to verify:
- Note field focused on open; typing fills it; Enter submits.
- Esc → navigation; ↑↓ move; Space toggles checkboxes; Space on note row re-enters edit.
- Long question/label/description wrap (resize terminal narrow to confirm no truncation mid-word).
- Esc in nav cancels (`Cancelled`); empty Enter submits `User submitted empty answer ...`.

---

## Self-Review

**Spec coverage:**
- Always multi-select → Task 2 checkboxes + `Space` toggle. ✓
- Custom note combinable, focused on open → Task 2 `mode="edit"`, cursor on note row, `formatResult` merges. ✓
- Wrap not truncate → Task 2 `wrapTextWithAnsi` for question/labels/descriptions; separator full-width. ✓
- Keys (Enter universal submit, Esc edit→nav, Esc nav→cancel, ↑↓, Space) → Task 2 `handleInput`. ✓
- Empty submit valid, not cancel → Task 1 `formatResult` empty branch + `isEmpty`; Task 2 returns `cancelled:false`. ✓
- Result reporting + `details` schema → Task 1 `content`, Task 2 `details`. ✓
- Zero options allowed → Task 1 test + Task 2 `(custom note only)` renderCall branch. ✓
- Params unchanged → Task 2 `QuestionParams` identical. ✓
- nix discovery / devLink → Task 2 git mv + home.nix edit. ✓

**Placeholder scan:** none — all steps contain full code/commands.

**Type consistency:** `formatResult`/`clampCursor`/`isNoteRow` signatures identical between Task 1 definition and Task 2 imports. `ResultModel` fields (`selected`, `note`, `content`, `isEmpty`) match shell usage. `QuestionDetails` consistent across execute/renderResult.
</content>
