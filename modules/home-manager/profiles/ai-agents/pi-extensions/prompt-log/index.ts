// prompt-log pi extension: logs every interactive prompt to a global sqlite DB
// and provides /prompts to search, star, tag, and recall past prompts. DB logic
// lives in db.ts; this file is the pi-facing imperative shell.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { DatabaseSync } from "node:sqlite";
import { join, basename, extname } from "node:path";
import { homedir, hostname } from "node:os";
import {
  openDb, logPrompt, searchPrompts, setStar, setTags,
  type PromptRow, type SearchFilters,
} from "./db.ts";

const DB_PATH = join(homedir(), ".pi", "agent", "prompts.db");

// "--starred --tool pi --since 2026-06-01 some words" -> { query, filters }.
export function parseArgs(args: string): { query: string; filters: SearchFilters } {
  const filters: SearchFilters = {};
  const words = (args ?? "").trim().split(/\s+/).filter(Boolean);
  const rest: string[] = [];
  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    if (w === "--starred") filters.starred = true;
    else if (w === "--host") filters.host = words[++i];
    else if (w === "--project") filters.project = words[++i];
    else if (w === "--tool") filters.tool = words[++i];
    else if (w === "--since") {
      const d = Date.parse(words[++i] ?? "");
      if (!Number.isNaN(d)) filters.since = d;
    } else rest.push(w);
  }
  return { query: rest.join(" "), filters };
}

// One-line, single-line label. Prefixed with #id so every label is unique
// (ctx.ui.select returns the chosen string; we map it back by value).
export function fmtRow(r: PromptRow): string {
  const star = r.starred ? "★ " : "  ";
  const date = new Date(r.ts_ms).toISOString().slice(0, 10);
  const oneLine = r.text.replace(/\s+/g, " ").trim().slice(0, 80);
  return `${star}#${r.id} [${r.source_tool}] ${date} — ${oneLine}`;
}

export default function (pi: ExtensionAPI) {
  // Lazy-opened, session-scoped DB handle (no resources from the factory itself).
  let db: DatabaseSync | null = null;
  const getDb = (): DatabaseSync => (db ??= openDb(DB_PATH));

  // Derive the session uuid from the session file name (<ts>_<uuid>.jsonl).
  const sessionId = (ctx: ExtensionContext): string | null => {
    const file = ctx.sessionManager?.getSessionFile?.();
    if (!file) return null;
    const stem = basename(file, extname(file));
    const idx = stem.indexOf("_");
    return idx >= 0 ? stem.slice(idx + 1) : stem;
  };

  pi.on("session_shutdown", () => {
    db?.close();
    db = null;
  });

  // Live logging: only prompts I actually type (skip rpc/extension-injected).
  pi.on("input", (event, ctx) => {
    if (event.source !== "interactive") return;
    const text = event.text?.trim();
    if (!text) return;
    try {
      logPrompt(getDb(), {
        ts_ms: Date.now(),
        hostname: hostname(),
        cwd: ctx.cwd,
        session_id: sessionId(ctx),
        source_tool: "pi",
        source: "interactive",
        text,
      });
    } catch (e) {
      // A logging failure must never block me from sending a prompt.
      ctx.ui.setStatus("prompt-log", `log failed: ${(e as Error).message}`);
    }
  });

  pi.registerCommand("prompts", {
    description: "Search, star, tag, and recall past prompts",
    handler: async (args, ctx) => {
      if (!ctx.hasUI) return;
      const { query, filters } = parseArgs(args);
      const rows = searchPrompts(getDb(), { query, filters, limit: 50 });
      if (rows.length === 0) {
        ctx.ui.notify("No matching prompts", "info");
        return;
      }

      // ctx.ui.select returns the chosen label string (or undefined). Labels are
      // unique via #id, so we recover the row by index of the picked label.
      const labels = rows.map(fmtRow);
      const picked = await ctx.ui.select("Prompts", labels);
      if (picked === undefined) return;
      const row = rows[labels.indexOf(picked)];
      if (!row) return;

      const STAR = row.starred ? "Unstar" : "Star";
      const action = await ctx.ui.select(`#${row.id}`, ["Recall to editor", STAR, "Edit tags"]);
      if (action === undefined) return;

      if (action === "Recall to editor") {
        ctx.ui.setEditorText(row.text);
      } else if (action === STAR) {
        setStar(getDb(), row.id, !row.starred);
        ctx.ui.notify(row.starred ? "Unstarred" : "Starred", "info");
      } else if (action === "Edit tags") {
        // editor() prefills existing tags so I can amend rather than retype.
        const tags = await ctx.ui.editor("Tags (space-separated)", row.tags ?? "");
        if (tags !== undefined) {
          setTags(getDb(), row.id, tags.trim());
          ctx.ui.notify("Tags updated", "info");
        }
      }
    },
  });
}
