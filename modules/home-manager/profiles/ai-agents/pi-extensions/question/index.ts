/**
 * Question Tool — always multi-select checkboxes + combinable custom note.
 * Full custom UI. First option is focused on open (note row sits last). ↑/↓
 * navigate all rows (options + note) and move into/out of the note field
 * directly; no edit/nav mode. Space toggles a checkbox on an option row, or
 * types into the note when the note row is focused. Enter submits the whole set
 * from anywhere; Esc cancels. All text wraps to terminal width (wrapTextWithAnsi).
 * An option may carry a short `tag` rendered as an accent-background pill before
 * its label (e.g. "recommended") so the agent can flag a preferred choice.
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
	visibleWidth,
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
	tag: Type.Optional(
		Type.String({
			description:
				'Short one-word badge shown before the label, e.g. "recommended". Use to flag a preferred option; list tagged options first.',
		}),
	),
	tagColor: Type.Optional(
		Type.Union(
			[
				Type.Literal("accent"),
				Type.Literal("success"),
				Type.Literal("warning"),
				Type.Literal("error"),
				Type.Literal("muted"),
			],
			{
				description:
					'Semantic color of the `tag` pill (default "accent"): success = safe/green, warning = caution/yellow, error = danger/red, muted = low-priority/grey.',
			},
		),
	),
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
			"Ask the user a question whenever you need their input — yes/no, single choice, multiple choice, or open-ended. Prefer this over asking in plain text. Each option is a checkbox (the user may pick any number) plus an optional free-form note. When you have a recommendation, tag the recommended option(s) and list them first.",
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
					// Cursor starts on the first option so it is focused on open; the note
					// row sits last (index params.options.length). Cursor position alone
					// determines behavior — no separate edit/nav mode (KISS): a single-line
					// note has no in-editor up/down, so arrows navigate rows globally.
					let cursor = 0;
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
						// Enter submits the whole set from anywhere.
						if (matchesKey(data, Key.enter)) {
							submit();
							return;
						}
						// Esc cancels from anywhere.
						if (matchesKey(data, Key.escape)) {
							done(null);
							return;
						}
						// Up/Down navigate rows globally — they move into and out of the
						// note field directly (no Esc/Space needed), since a single-line
						// note has no in-editor up/down meaning.
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
						// On the note row the editor is active: forward all other input
						// (including Space, which types a space into the note).
						if (isNoteRow(cursor, params.options.length)) {
							editor.handleInput(data);
							refresh();
							return;
						}
						// Option row: Space toggles its checkbox.
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
						// Prefix is shown at the start of every wrapped line; its VISIBLE
						// width (ANSI stripped) is subtracted from the wrap budget so styled
						// gutters/pointers don't push text past the terminal edge.
						// style receives the wrapped-line index so callers can treat the first
						// line specially (e.g. an option's tag badge only sits on line 0).
						const addWrapped = (raw: string, prefix: string, style: (t: string, lineIdx: number) => string) => {
							const wrapped = wrapTextWithAnsi(raw, Math.max(1, width - visibleWidth(prefix)));
							for (let li = 0; li < wrapped.length; li++) {
								lines.push(truncateToWidth(prefix + style(wrapped[li], li), width));
							}
						};

						lines.push(truncateToWidth(theme.fg("accent", "─".repeat(width)), width));
						addWrapped(params.question, " ", (t) => theme.fg("text", t));
						lines.push("");

						for (let i = 0; i < params.options.length; i++) {
							const opt = params.options[i];
							const onRow = cursor === i;
							const box = checked[i] ? "[x]" : "[ ]";
							// 2-col gutter: "> " (accent) when focused, "  " otherwise.
							const prefix = onRow ? theme.fg("accent", "> ") : "  ";
							const labelStyle = (t: string) =>
								onRow || checked[i] ? theme.fg("accent", t) : theme.fg("text", t);
							// Tag rendered as an accent-background pill (reverse video on accent fg)
							// before the label, first wrapped line only. The pill's pad spaces are
							// part of the RAW text so wrap-width math matches the visible width; the
							// pill piece is self-coloured+reset, so per-line SGR reset stays correct.
							const pill = opt.tag ? ` ${opt.tag} ` : "";
							const pillColor = opt.tagColor ?? "accent";
							const tagRaw = pill ? `${pill} ` : "";
							addWrapped(`${box} ${i + 1}. ${tagRaw}${opt.label}`, prefix, (t, li) => {
								if (li === 0 && pill) {
									const at = t.indexOf(pill);
									if (at >= 0)
										return (
											labelStyle(t.slice(0, at)) +
											theme.inverse(theme.fg(pillColor, pill)) +
											labelStyle(t.slice(at + pill.length))
										);
								}
								return labelStyle(t);
							});
							if (opt.description) {
								// 9 cols = 2 gutter + len("[x] N. "), so description aligns under label.
								addWrapped(opt.description, "         ", (t) => theme.fg("muted", t));
							}
						}

						lines.push("");
						const noteFocused = isNoteRow(cursor, params.options.length);
						const notePointer = noteFocused ? theme.fg("accent", "> ") : "  ";
						lines.push(truncateToWidth(notePointer + theme.fg("muted", "Note:") + (noteFocused ? theme.fg("accent", " ✎") : ""), width));
						for (const line of editor.render(width - 2)) {
							lines.push(truncateToWidth(` ${line}`, width));
						}

						lines.push("");
						const hint = " ↑↓ move • Space toggle • Enter submit • Esc cancel";
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
