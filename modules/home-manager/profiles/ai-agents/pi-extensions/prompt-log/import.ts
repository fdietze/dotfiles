// One-time backfill: import historical prompts from pi, Claude Code, and Codex
// into the prompt-log DB. Idempotent (INSERT OR IGNORE) -> safe to re-run.
// Run: node ~/.pi/agent/extensions/prompt-log/import.ts
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir, hostname } from "node:os";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import { openDb, logPrompt, type NewPrompt } from "./db.ts";
import { parsePiSession, parseClaudeHistory, parseCodexHistory } from "./sources.ts";

const HOME = homedir();
const DB_PATH = join(HOME, ".pi", "agent", "prompts.db");

// Recursively collect *.jsonl under dir, skipping subagent sessions (those are
// agent-to-agent, not prompts I typed).
export function piSessionFiles(dir: string): string[] {
  const out: string[] = [];
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) {
      if (name === "subagents") continue;
      out.push(...piSessionFiles(p));
    } else if (name.endsWith(".jsonl")) {
      out.push(p);
    }
  }
  return out;
}

interface IngestStat { read: number; inserted: number; }

// Insert rows, stamping each with the current hostname (all history is local).
export function ingest(db: DatabaseSync, rows: NewPrompt[]): IngestStat {
  const host = hostname();
  let inserted = 0;
  for (const r of rows) if (logPrompt(db, { ...r, hostname: host })) inserted++;
  return { read: rows.length, inserted };
}

export function main(): void {
  const db = openDb(DB_PATH);

  const pi: IngestStat = { read: 0, inserted: 0 };
  for (const f of piSessionFiles(join(HOME, ".pi", "agent", "sessions"))) {
    const s = ingest(db, parsePiSession(readFileSync(f, "utf8")));
    pi.read += s.read;
    pi.inserted += s.inserted;
  }

  const claudeFile = join(HOME, ".claude", "history.jsonl");
  const claude = existsSync(claudeFile)
    ? ingest(db, parseClaudeHistory(readFileSync(claudeFile, "utf8")))
    : { read: 0, inserted: 0 };

  const codexFile = join(HOME, ".codex", "history.jsonl");
  const codex = existsSync(codexFile)
    ? ingest(db, parseCodexHistory(readFileSync(codexFile, "utf8")))
    : { read: 0, inserted: 0 };

  db.close();
  for (const [tool, s] of [["pi", pi], ["claude", claude], ["codex", codex]] as const) {
    console.log(`${tool}: read ${s.read}, inserted ${s.inserted}, skipped ${s.read - s.inserted}`);
  }
}

// Run only when invoked directly, so tests can import ingest/piSessionFiles safely.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
