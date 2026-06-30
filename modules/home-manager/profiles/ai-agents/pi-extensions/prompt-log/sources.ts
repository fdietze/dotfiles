// Pure parsers that normalize external agent history files into NewPrompt rows.
// No IO, no DB -> unit-testable with fixture strings. hostname is filled in by the
// caller (import.ts), since all this history originates from the current machine.
import type { NewPrompt } from "./db.ts";

// Yield parsed objects for each non-empty JSONL line; skip malformed lines.
function* jsonLines(content: string): Generator<any> {
  for (const line of content.split("\n")) {
    const s = line.trim();
    if (!s) continue;
    try {
      yield JSON.parse(s);
    } catch {
      /* skip malformed line */
    }
  }
}

// pi session jsonl: a {type:"session"} header carries id + cwd; user prompts are
// {type:"message", message:{role:"user", content:[{type:"text",text}]}}.
export function parsePiSession(content: string): NewPrompt[] {
  let cwd: string | null = null;
  let sessionId: string | null = null;
  const out: NewPrompt[] = [];
  for (const e of jsonLines(content)) {
    if (e.type === "session") {
      cwd = e.cwd ?? null;
      sessionId = e.id ?? null;
      continue;
    }
    if (e.type === "message" && e.message?.role === "user") {
      const text = (e.message.content ?? [])
        .filter((c: any) => c?.type === "text")
        .map((c: any) => c.text)
        .join("")
        .trim();
      if (!text) continue;
      out.push({
        ts_ms: e.timestamp ? Date.parse(e.timestamp) : 0,
        cwd,
        session_id: sessionId,
        source_tool: "pi",
        source: "pi",
        text,
      });
    }
  }
  return out;
}

// claude ~/.claude/history.jsonl: {display, timestamp(ms), project, sessionId}.
export function parseClaudeHistory(content: string): NewPrompt[] {
  const out: NewPrompt[] = [];
  for (const e of jsonLines(content)) {
    const text = (e.display ?? "").trim();
    if (!text) continue;
    out.push({
      ts_ms: typeof e.timestamp === "number" ? e.timestamp : 0,
      cwd: e.project ?? null,
      session_id: e.sessionId ?? null,
      source_tool: "claude",
      source: "claude",
      text,
    });
  }
  return out;
}

// codex ~/.codex/history.jsonl: {text, ts(seconds), session_id}. No project field.
export function parseCodexHistory(content: string): NewPrompt[] {
  const out: NewPrompt[] = [];
  for (const e of jsonLines(content)) {
    const text = (e.text ?? "").trim();
    if (!text) continue;
    out.push({
      ts_ms: typeof e.ts === "number" ? e.ts * 1000 : 0,
      cwd: null,
      session_id: e.session_id ?? null,
      source_tool: "codex",
      source: "codex",
      text,
    });
  }
  return out;
}
