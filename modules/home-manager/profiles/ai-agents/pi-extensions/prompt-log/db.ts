// Shared sqlite core for the prompt-log extension. No pi imports, so it is
// unit-testable standalone and reused by both index.ts (live) and import.ts
// (backfill). Uses the builtin node:sqlite (FTS5 is compiled into Node's sqlite).
import { DatabaseSync } from "node:sqlite";

export interface NewPrompt {
  ts_ms: number;
  hostname?: string | null;
  cwd?: string | null;
  session_id?: string | null;
  source_tool: string; // 'pi' | 'claude' | 'codex'
  source?: string | null; // 'interactive' for live, tool name for imports
  text: string;
}

export interface PromptRow {
  id: number;
  ts_ms: number;
  hostname: string | null;
  cwd: string | null;
  session_id: string | null;
  source_tool: string;
  source: string | null;
  text: string;
  starred: number;
  tags: string | null;
}

export interface SearchFilters {
  starred?: boolean;
  host?: string;
  project?: string; // substring match on cwd
  tool?: string; // exact source_tool
  since?: number; // ts_ms lower bound (inclusive)
}

// Open (creating if needed) the prompt DB and ensure the schema exists.
// WAL + busy_timeout: multiple concurrent pi instances write to this file.
export function openDb(path: string): DatabaseSync {
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL;");
  db.exec("PRAGMA busy_timeout=5000;");
  db.exec(`
    CREATE TABLE IF NOT EXISTS prompts (
      id          INTEGER PRIMARY KEY,
      ts_ms       INTEGER NOT NULL,
      hostname    TEXT,
      cwd         TEXT,
      session_id  TEXT,
      source_tool TEXT NOT NULL,
      source      TEXT,
      text        TEXT NOT NULL,
      starred     INTEGER NOT NULL DEFAULT 0,
      tags        TEXT,
      UNIQUE(source_tool, session_id, text)
    );
    CREATE VIRTUAL TABLE IF NOT EXISTS prompts_fts
      USING fts5(text, content='prompts', content_rowid='id');
    CREATE TRIGGER IF NOT EXISTS prompts_ai AFTER INSERT ON prompts BEGIN
      INSERT INTO prompts_fts(rowid, text) VALUES (new.id, new.text);
    END;
  `);
  return db;
}

// Insert a prompt; dedup via UNIQUE(source_tool, session_id, text) with
// INSERT OR IGNORE (first-inserted wins). Returns true if a row was added.
export function logPrompt(db: DatabaseSync, p: NewPrompt): boolean {
  const r = db
    .prepare(
      `INSERT OR IGNORE INTO prompts
         (ts_ms, hostname, cwd, session_id, source_tool, source, text)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(
      p.ts_ms,
      p.hostname ?? null,
      p.cwd ?? null,
      p.session_id ?? null,
      p.source_tool,
      p.source ?? null,
      p.text,
    );
  return r.changes === 1;
}
