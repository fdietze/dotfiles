/**
 * SwarmPanel — Vollbild-Takeover (kein Overlay; Overlays froren die TUI ein).
 * Muster gespiegelt von question.ts: Factory liefert { render, handleInput, invalidate },
 * Editor via new Editor(tui, theme), Refresh über tui.requestRender().
 * Transcript reuses the real chat components (User/Assistant/ToolExecution) for parity
 * with the main chat; the agent's system prompt is shown at the top. Defensive try/catch
 * around each component falls back to plain text so a render error never freezes the TUI.
 */
import { Editor, type EditorTheme, Key, matchesKey, truncateToWidth } from "@earendil-works/pi-tui";
import { AssistantMessageComponent, ToolExecutionComponent, UserMessageComponent } from "@earendil-works/pi-coding-agent";
import type { Engine } from "./engine.ts";
import {
	clampScroll,
	formatContext,
	formatRosterRow,
	findToolResult,
	messageText,
	moveSelection,
	toolCalls,
} from "./panel-logic.ts";

interface PanelDeps {
	engine: Engine;
	route: (to: string, content: string) => void;
	cwd: string;
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

	// Tool-Call wie im Haupt-Chat rendern (echte ToolExecutionComponent, inkl. Ergebnis).
	const renderToolCall = (call: { id: string; name: string; arguments: unknown }, msgs: RawMessage[], width: number) =>
		renderComponentLines(
			() => {
				const comp = new ToolExecutionComponent(
					call.name,
					call.id,
					call.arguments,
					{ showImages: false },
					undefined as never,
					tui as never,
					deps.cwd,
				);
				comp.setArgsComplete();
				const res = findToolResult(msgs as { role?: string; toolCallId?: string }[], call.id);
				if (res) comp.updateResult(res as never);
				return comp;
			},
			width,
			`⚙ ${call.name}`,
		);

	const transcriptLines = (width: number): string[] => {
		const rec = actors()[selectedIndex];
		if (!rec) return [theme.fg("muted", "  (keine Agents — mit spawn_agent erzeugen)")];
		const msgs = (rec.view?.getMessages() ?? []) as RawMessage[];
		const lines: string[] = [];
		// System-Prompt oben anzeigen (steht nicht in messages[]).
		const sys = rec.view?.getSystemPrompt?.();
		if (sys) {
			lines.push(theme.fg("dim", truncateToWidth("─ system ─", width)));
			for (const l of sys.split("\n")) lines.push(theme.fg("dim", truncateToWidth(`  ${l}`, width)));
			lines.push("");
		}
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
				// Tool-Calls separat wie im Haupt-Chat (toolResult wird inline gemerged).
				for (const call of toolCalls(m)) lines.push(...renderToolCall(call, msgs, width));
			}
			// toolResult-Rollen werden inline beim zugehörigen toolCall gerendert (übersprungen).
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
			const header = `─ agents · ${actors().length} agents · ${running} running · budget ${used}/${total} `;
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
					? theme.bg("infoBg", truncateToWidth(" ⏸ agents HALTED — /unhalt to resume ".padEnd(width), width))
					: theme.bg("selectedBg", " ▶ running "),
			);
			lines.push(theme.fg("dim", truncateToWidth("─".repeat(width), width)));
			lines.push(...transcriptLines(width));
			// Ziel-Label + Chatbox (der Editor zeichnet seinen eigenen Rahmen → keine extra Trennlinie).
			const target = selectedName();
			lines.push(theme.fg("muted", truncateToWidth(target ? ` → an ${target}:` : " (kein Agent gewählt)", width)));
			lines.push(...editor.render(width));
			const scrollHint = `${hasAbove ? "▲" : ""}${hasBelow ? "▼" : ""}`;
			lines.push(
				theme.fg(
					"dim",
					truncateToWidth(` ↑/↓ Agent · Ctrl+U/D scroll ${scrollHint} · Enter senden · Esc schließen `, width),
				),
			);
			return lines;
		},
		invalidate(): void {
			(editor as { invalidate?: () => void }).invalidate?.();
		},
	};
}
