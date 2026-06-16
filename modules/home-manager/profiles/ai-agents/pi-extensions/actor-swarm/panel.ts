/**
 * SwarmPanel — Vollbild-Takeover (kein Overlay; Overlays froren die TUI ein).
 * Muster gespiegelt von question.ts: Factory liefert { render, handleInput, invalidate },
 * Editor via new Editor(tui, theme), Refresh über tui.requestRender().
 * Transcript wird in Phase-2.1 schlicht als Text gerendert (role + Inhalt);
 * Upgrade auf die Original-Message-Components ist additiv möglich.
 */
import { Editor, type EditorTheme, Key, matchesKey, truncateToWidth } from "@earendil-works/pi-tui";
import { AssistantMessageComponent, UserMessageComponent } from "@earendil-works/pi-coding-agent";
import type { Engine } from "./engine.ts";
import { clampScroll, formatContext, formatRosterRow, messageText, moveSelection, toolCallLabels } from "./panel-logic.ts";

interface PanelDeps {
	engine: Engine;
	route: (to: string, content: string) => void;
}

interface TuiLike {
	requestRender(): void;
}
interface ThemeLike {
	fg(color: string, s: string): string;
}

const TRANSCRIPT_VIEWPORT = 14;

interface RawMessage {
	role?: string;
	content?: unknown;
}

// Original-Message-Component defensiv rendern; bei Form-Abweichung Fallback auf Text,
// damit ein Render-Fehler nie die TUI einfriert.
function renderComponentLines(make: () => { render(w: number): string[] }, width: number, fallback: string): string[] {
	try {
		return make().render(width);
	} catch {
		return fallback.split("\n").map((l) => truncateToWidth(`  ${l}`, width));
	}
}

export function createSwarmPanel(deps: PanelDeps, tui: TuiLike, theme: ThemeLike, done: () => void) {
	let selectedIndex = 0;
	let scrollOffset = 0;
	let unsubView: (() => void) | undefined;

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
	const editor = new Editor(tui as never, editorTheme);

	const actors = () => deps.engine.list();
	const refresh = () => tui.requestRender();
	const selectedName = () => actors()[selectedIndex]?.name;

	// Auf die View des gewählten Actors abonnieren, damit Streaming live nachzieht.
	const rebindView = () => {
		unsubView?.();
		unsubView = undefined;
		const rec = actors()[selectedIndex];
		if (rec?.view) unsubView = rec.view.subscribe(() => refresh());
	};
	rebindView();

	editor.onSubmit = (value: string) => {
		const to = selectedName();
		const text = value.trim();
		if (to && text) {
			deps.route(to, text);
			editor.setText("");
			refresh();
		}
	};

	const transcriptLines = (width: number): string[] => {
		const rec = actors()[selectedIndex];
		if (!rec) return [theme.fg("muted", "  (no actor)")];
		if (rec.name === "user") return [theme.fg("muted", "  = Haupt-Chat (verlasse das Panel mit Esc) =")];
		const msgs = (rec.view?.getMessages() ?? []) as RawMessage[];
		const lines: string[] = [];
		for (const m of msgs) {
			if (m.role === "user") {
				const text = messageText(m.content);
				lines.push(...renderComponentLines(() => new UserMessageComponent(text, undefined as never), width, text));
			} else if (m.role === "assistant") {
				lines.push(
					...renderComponentLines(
						() => new AssistantMessageComponent(m as never, false, undefined as never),
						width,
						messageText(m.content),
					),
				);
				for (const label of toolCallLabels(m)) lines.push(theme.fg("dim", truncateToWidth(`  ${label}`, width)));
			} else if (m.role === "toolResult") {
				lines.push(theme.fg("dim", truncateToWidth(`  ⚙ → ${messageText(m.content)}`, width)));
			}
		}
		if (lines.length === 0) lines.push(theme.fg("muted", "  (noch keine Nachrichten)"));
		scrollOffset = clampScroll(scrollOffset, lines.length, TRANSCRIPT_VIEWPORT);
		return lines.slice(scrollOffset, scrollOffset + TRANSCRIPT_VIEWPORT);
	};

	const close = () => {
		unsubView?.();
		unsubView = undefined;
		done();
	};

	return {
		handleInput(data: string): void {
			if (matchesKey(data, Key.escape)) {
				close();
				return;
			}
			if (matchesKey(data, Key.up)) {
				selectedIndex = moveSelection(selectedIndex, -1, actors().length);
				scrollOffset = 0;
				rebindView();
				refresh();
				return;
			}
			if (matchesKey(data, Key.down)) {
				selectedIndex = moveSelection(selectedIndex, 1, actors().length);
				scrollOffset = 0;
				rebindView();
				refresh();
				return;
			}
			if (matchesKey(data, Key.pageUp)) {
				scrollOffset -= 5;
				refresh();
				return;
			}
			if (matchesKey(data, Key.pageDown)) {
				scrollOffset += 5;
				refresh();
				return;
			}
			editor.handleInput(data);
			refresh();
		},
		render(width: number): string[] {
			const lines: string[] = [];
			lines.push(theme.fg("accent", truncateToWidth("─ swarm ".padEnd(width, "─"), width)));
			actors().forEach((a, i) => {
				lines.push(
					formatRosterRow(
						{ name: a.name, context: formatContext(a.view?.getContextUsage()), active: a.streaming },
						i === selectedIndex,
						width,
					),
				);
			});
			lines.push(theme.fg("dim", truncateToWidth("─".repeat(width), width)));
			lines.push(...transcriptLines(width));
			lines.push(theme.fg("dim", truncateToWidth("─".repeat(width), width)));
			lines.push(...editor.render(width));
			lines.push(theme.fg("dim", truncateToWidth(" ↑/↓ Actor · PgUp/PgDn scroll · Enter senden · Esc schließen ", width)));
			return lines;
		},
		invalidate(): void {
			(editor as { invalidate?: () => void }).invalidate?.();
		},
	};
}
