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
	bg(color: string, s: string): string;
}

// active = gut sichtbarer Hintergrund, idle = dezent.
const styleStatus = (theme: ThemeLike) => (label: string, active: boolean) =>
	active ? theme.bg("toolSuccessBg", label) : theme.fg("dim", label);

const TRANSCRIPT_VIEWPORT = 18;

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
	let followBottom = true; // standardmäßig neueste Zeilen zeigen
	let hasAbove = false;
	let hasBelow = false;
	const SCROLL_STEP = 5;
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

	// 'user' wird im Panel nicht gelistet (= der Haupt-Chat, in dem man ohnehin ist).
	const actors = () => deps.engine.list().filter((a) => a.name !== "user");
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
		if (!rec) return [theme.fg("muted", "  (keine Actors — mit spawn_agent erzeugen)")];
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
				// Mehrzeilige Ergebnisse sauber einrücken und auf wenige Zeilen begrenzen.
				const resultLines = messageText(m.content).trim().split("\n");
				const MAX = 3;
				resultLines.slice(0, MAX).forEach((line, i) => {
					lines.push(theme.fg("dim", truncateToWidth(`  ${i === 0 ? "⚙ →" : "   "} ${line}`, width)));
				});
				if (resultLines.length > MAX) {
					lines.push(theme.fg("dim", truncateToWidth(`      … (+${resultLines.length - MAX} lines)`, width)));
				}
			}
		}
		if (lines.length === 0) lines.push(theme.fg("muted", "  (noch keine Nachrichten)"));
		const max = Math.max(0, lines.length - TRANSCRIPT_VIEWPORT);
		if (followBottom || scrollOffset >= max) {
			scrollOffset = max;
			followBottom = true;
		} else {
			scrollOffset = clampScroll(scrollOffset, lines.length, TRANSCRIPT_VIEWPORT);
		}
		hasAbove = scrollOffset > 0;
		hasBelow = scrollOffset < max;
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
				followBottom = true;
				rebindView();
				refresh();
				return;
			}
			if (matchesKey(data, Key.down)) {
				selectedIndex = moveSelection(selectedIndex, 1, actors().length);
				followBottom = true;
				rebindView();
				refresh();
				return;
			}
			// Scroll-Up: PgUp / Ctrl+U / Shift+Up (mehrere, da tmux/Terminal PgUp evtl. abfängt)
			if (matchesKey(data, Key.pageUp) || matchesKey(data, Key.ctrl("u")) || matchesKey(data, Key.shift("up"))) {
				followBottom = false;
				scrollOffset = Math.max(0, scrollOffset - SCROLL_STEP);
				refresh();
				return;
			}
			// Scroll-Down: PgDn / Ctrl+D / Shift+Down
			if (matchesKey(data, Key.pageDown) || matchesKey(data, Key.ctrl("d")) || matchesKey(data, Key.shift("down"))) {
				scrollOffset += SCROLL_STEP; // render re-stickt ans Ende, wenn am Boden
				refresh();
				return;
			}
			editor.handleInput(data);
			refresh();
		},
		render(width: number): string[] {
			const lines: string[] = [];
			const running = deps.engine.list().filter((a) => a.streaming).length;
			const { used, total } = deps.engine.budget;
			const header = `─ swarm · ${actors().length} actors · ${running} running · budget ${used}/${total} `;
			lines.push(theme.fg("accent", truncateToWidth(header.padEnd(width, "─"), width)));
			const styler = styleStatus(theme);
			actors().forEach((a, i) => {
				lines.push(
					formatRosterRow(
						{ name: a.name, context: formatContext(a.view?.getContextUsage()), active: a.streaming },
						i === selectedIndex,
						width,
						styler,
					),
				);
			});
			// Halt/Unhalt-Zustand klar unter der Liste anzeigen.
			lines.push(
				deps.engine.isFrozen()
					? theme.bg("infoBg", truncateToWidth(" ⏸ swarm HALTED — /unhalt to resume ".padEnd(width), width))
					: theme.bg("selectedBg", " ▶ running "),
			);
			lines.push(theme.fg("dim", truncateToWidth("─".repeat(width), width)));
			lines.push(...transcriptLines(width));
			// Ziel-Label + Chatbox (der Editor zeichnet seinen eigenen Rahmen → keine extra Trennlinie).
			const target = selectedName();
			lines.push(theme.fg("muted", truncateToWidth(target ? ` → an ${target}:` : " (kein Actor gewählt)", width)));
			lines.push(...editor.render(width));
			const scrollHint = `${hasAbove ? "▲" : ""}${hasBelow ? "▼" : ""}`;
			lines.push(
				theme.fg(
					"dim",
					truncateToWidth(` ↑/↓ Actor · Ctrl+U/D scroll ${scrollHint} · Enter senden · Esc schließen `, width),
				),
			);
			return lines;
		},
		invalidate(): void {
			(editor as { invalidate?: () => void }).invalidate?.();
		},
	};
}
