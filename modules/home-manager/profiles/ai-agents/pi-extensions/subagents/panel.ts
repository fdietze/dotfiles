/**
 * SubagentsPanel — fullscreen takeover (no overlay; overlays froze the TUI).
 * Pattern mirrored from question.ts: the factory returns { render, handleInput, invalidate },
 * editor via new Editor(tui, theme), refresh via tui.requestRender().
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
	mergeStreaming,
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

// active = clearly visible background, idle = subtle.
const styleStatus = (theme: ThemeLike) => (label: string, active: boolean) =>
	active ? theme.bg("toolSuccessBg", label) : theme.fg("dim", label);

const TRANSCRIPT_VIEWPORT = 18;

interface RawMessage {
	role?: string;
	content?: unknown;
}

// Render the original message component defensively; fall back to text on shape mismatch,
// so a render error never freezes the TUI.
function renderComponentLines(make: () => { render(w: number): string[] }, width: number, fallback: string): string[] {
	try {
		return make().render(width);
	} catch {
		return fallback.split("\n").map((l) => truncateToWidth(`  ${l}`, width));
	}
}

export function createSubagentsPanel(deps: PanelDeps, tui: TuiLike, theme: ThemeLike, done: () => void) {
	let selectedIndex = 0;
	let scrollOffset = 0;
	let followBottom = true; // show the newest lines by default
	let hasAbove = false;
	let hasBelow = false;
	const SCROLL_STEP = 5;
	let unsubView: (() => void) | undefined;
	// Live in-progress assistant message of the selected agent, captured from streaming
	// events (message_start/update). interactive-mode.js feeds event.message into a
	// streamingComponent the same way; session.messages is not relied on mid-turn.
	let streamingMessage: RawMessage | undefined;

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

	// 'main' is not listed in the panel (= the main chat you are already in).
	const agents = () => deps.engine.list().filter((a) => a.name !== "main");
	const refresh = () => tui.requestRender();
	const selectedName = () => agents()[selectedIndex]?.name;

	// Subscribe to the selected agent's view so streaming updates live.
	const rebindView = () => {
		unsubView?.();
		unsubView = undefined;
		streamingMessage = undefined;
		const rec = agents()[selectedIndex];
		if (rec?.view)
			unsubView = rec.view.subscribe((e) => {
				const msg = e.message as RawMessage | undefined;
				if (msg?.role === "assistant") {
					streamingMessage = e.type === "message_end" ? undefined : msg;
				}
				refresh();
			});
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

	// Render the tool call like the main chat (real ToolExecutionComponent, incl. result).
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
		const rec = agents()[selectedIndex];
		if (!rec) return [theme.fg("muted", "  (no agents — create one with spawn_agent)")];
		// Merge the live streaming message so tokens appear as they arrive (deduped if the
		// session already holds it).
		const msgs = mergeStreaming((rec.view?.getMessages() ?? []) as RawMessage[], streamingMessage);
		const lines: string[] = [];
		// Show the system prompt at the top (it is not part of messages[]).
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
				// Tool calls rendered separately like the main chat (toolResult merged inline).
				for (const call of toolCalls(m)) lines.push(...renderToolCall(call, msgs, width));
			}
			// toolResult roles are rendered inline with their toolCall (skipped here).
		}
		if (lines.length === 0) lines.push(theme.fg("muted", "  (no messages yet)"));
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
				selectedIndex = moveSelection(selectedIndex, -1, agents().length);
				followBottom = true;
				rebindView();
				refresh();
				return;
			}
			if (matchesKey(data, Key.down)) {
				selectedIndex = moveSelection(selectedIndex, 1, agents().length);
				followBottom = true;
				rebindView();
				refresh();
				return;
			}
			// Scroll up: PgUp / Ctrl+U / Shift+Up (several, since tmux/terminal may swallow PgUp)
			if (matchesKey(data, Key.pageUp) || matchesKey(data, Key.ctrl("u")) || matchesKey(data, Key.shift("up"))) {
				followBottom = false;
				scrollOffset = Math.max(0, scrollOffset - SCROLL_STEP);
				refresh();
				return;
			}
			// Scroll-Down: PgDn / Ctrl+D / Shift+Down
			if (matchesKey(data, Key.pageDown) || matchesKey(data, Key.ctrl("d")) || matchesKey(data, Key.shift("down"))) {
				scrollOffset += SCROLL_STEP; // render re-sticks to the bottom when at the end
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
			const header = `─ agents · ${agents().length} agents · ${running} running · budget ${used}/${total} `;
			lines.push(theme.fg("accent", truncateToWidth(header.padEnd(width, "─"), width)));
			const styler = styleStatus(theme);
			agents().forEach((a, i) => {
				lines.push(
					formatRosterRow(
						{ name: a.name, model: a.model, context: formatContext(a.view?.getContextUsage()), active: a.streaming },
						i === selectedIndex,
						width,
						styler,
					),
				);
			});
			// Show the halt/unhalt state clearly below the list.
			lines.push(
				deps.engine.isFrozen()
					? theme.bg("toolPendingBg", truncateToWidth(" ⏸ agents HALTED — /unhalt to resume ".padEnd(width), width))
					: theme.bg("selectedBg", " ▶ running "),
			);
			lines.push(theme.fg("dim", truncateToWidth("─".repeat(width), width)));
			lines.push(...transcriptLines(width));
			// Chatbox (the editor draws its own frame → no extra separator line).
			if (!selectedName()) lines.push(theme.fg("muted", truncateToWidth(" (no agent selected)", width)));
			lines.push(...editor.render(width));
			const scrollHint = `${hasAbove ? "▲" : ""}${hasBelow ? "▼" : ""}`;
			lines.push(
				theme.fg(
					"dim",
					truncateToWidth(` ↑/↓ agent · Ctrl+U/D scroll ${scrollHint} · Enter send · Esc close `, width),
				),
			);
			return lines;
		},
		invalidate(): void {
			(editor as { invalidate?: () => void }).invalidate?.();
		},
	};
}
