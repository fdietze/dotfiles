# prompt-log pi extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pi extension that logs every interactive prompt I type into a global sqlite DB, backfills history from pi/Claude/Codex, and lets me full-text search, star, tag, and recall past prompts — with prompt text write-once.

**Architecture:** Directory-style pi extension under `pi-extensions/prompt-log/`. A dependency-free sqlite core (`db.ts`, uses builtin `node:sqlite` + FTS5) is reused by the live-logging extension (`index.ts`) and a one-time backfill CLI (`import.ts`). Pure history parsers (`sources.ts`) normalize the three tools' history files. nix auto-symlinks the dir; pi loads only `index.ts`, the rest stays inert.

**Tech Stack:** TypeScript run natively by Node 24 (no compile); `node:sqlite` (FTS5 verified present); `node:test` for tests; pi extension API (`input` event, `registerCommand`, `ctx.ui`).

## Global Constraints

- **Zero npm dependencies.** Use only Node builtins: `node:sqlite`, `node:os`, `node:fs`, `node:path`, `node:url`. No `package.json`.
- **Imports use explicit `.ts` extensions** (e.g. `from "./db.ts"`) — required by Node native TS and handled by pi's jiti loader.
- **DB path:** `~/.pi/agent/prompts.db` (`join(os.homedir(), ".pi", "agent", "prompts.db")`).
- **Prompt text is write-once.** The only `UPDATE` statements allowed in the whole codebase touch `starred` and `tags`. No statement may ever `UPDATE` or `DELETE` `text`.
- **Source tools:** `'pi' | 'claude' | 'codex'`.
- **Dedup key:** `UNIQUE(source_tool, session_id, text)`; inserts use `INSERT OR IGNORE`; first-inserted wins.
- **Test command:** run inside the extension dir: `node --test`. Test files end in `.test.ts` (stay inert in pi).
- **Run all `node`/`node --test` commands from** `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/`.

## File Structure

```
modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/
├── db.ts            # sqlite core: schema, openDb, logPrompt, searchPrompts, setStar, setTags
├── sources.ts       # pure parsers: parsePiSession, parseClaudeHistory, parseCodexHistory
├── import.ts        # one-time backfill CLI (walks files, calls sources + db)
├── index.ts         # pi extension: live input logging + /prompts command
├── db.test.ts       # unit tests for db.ts
└── sources.test.ts  # unit tests for sources.ts (+ parseArgs/fmtRow from index.ts)
```

---

### Task 1: sqlite core — schema, open, insert + dedup

**Files:**
- Create: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/db.ts`
- Test: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/db.test.ts`

**Interfaces:**
- Consumes: nothing (leaf module).
- Produces:
  - `interface NewPrompt { ts_ms: number; hostname?: string | null; cwd?: string | null; session_id?: string | null; source_tool: string; source?: string | null; text: string; }`
  - `interface PromptRow { id: number; ts_ms: number; hostname: string | null; cwd: string | null; session_id: string | null; source_tool: string; source: string | null; text: string; starred: number; tags: string | null; }`
  - `interface SearchFilters { starred?: boolean; host?: string; project?: string; tool?: string; since?: number; }`
  - `function openDb(path: string): DatabaseSync`
  - `function logPrompt(db: DatabaseSync, p: NewPrompt): boolean` — true if a row was inserted

- [ ] **Step 1: Write the failing test**

Create `db.test.ts`:

```typescript
import { test } from "node:test";
import assert from "node:assert";
import { openDb, logPrompt } from "./db.ts";

test("logPrompt inserts a row and returns true", () => {
  const db = openDb(":memory:");
  const inserted = logPrompt(db, {
    ts_ms: 1000, cwd: "/p", session_id: "s1", source_tool: "pi", source: "interactive", text: "hello world",
  });
  assert.equal(inserted, true);
  const row = db.prepare("SELECT * FROM prompts").get() as any;
  assert.equal(row.text, "hello world");
  assert.equal(row.source_tool, "pi");
  assert.equal(row.starred, 0);
});

test("dedup on (source_tool, session_id, text): second insert ignored", () => {
  const db = openDb(":memory:");
  const p = { ts_ms: 1, session_id: "s1", source_tool: "pi", text: "same" };
  assert.equal(logPrompt(db, { ...p, ts_ms: 1 }), true);
  assert.equal(logPrompt(db, { ...p, ts_ms: 2 }), false); // drifted ts still dedups
  assert.equal((db.prepare("SELECT COUNT(*) c FROM prompts").get() as any).c, 1);
});

test("same text in different session is not deduped", () => {
  const db = openDb(":memory:");
  logPrompt(db, { ts_ms: 1, session_id: "s1", source_tool: "pi", text: "x" });
  logPrompt(db, { ts_ms: 1, session_id: "s2", source_tool: "pi", text: "x" });
  assert.equal((db.prepare("SELECT COUNT(*) c FROM prompts").get() as any).c, 2);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test`
Expected: FAIL — `Cannot find module './db.ts'` / `openDb is not a function`.

- [ ] **Step 3: Write minimal implementation**

Create `db.ts`:

```typescript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test`
Expected: PASS — 3 tests (ignore the `ExperimentalWarning` for `node:sqlite`).

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/db.ts \
        modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/db.test.ts
git commit -m "feat(prompt-log): sqlite core with schema, openDb, logPrompt + dedup"
```

---

### Task 2: search, star, tag

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/db.ts` (append functions)
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/db.test.ts` (append tests)

**Interfaces:**
- Consumes: `openDb`, `logPrompt`, `PromptRow`, `SearchFilters` from Task 1.
- Produces:
  - `function searchPrompts(db: DatabaseSync, opts?: { query?: string; filters?: SearchFilters; limit?: number }): PromptRow[]`
  - `function setStar(db: DatabaseSync, id: number, starred: boolean): void`
  - `function setTags(db: DatabaseSync, id: number, tags: string): void`

- [ ] **Step 1: Write the failing test**

Append to `db.test.ts`:

```typescript
import { searchPrompts, setStar, setTags } from "./db.ts";

function seed() {
  const db = openDb(":memory:");
  logPrompt(db, { ts_ms: 10, hostname: "h1", cwd: "/a/proj", session_id: "s1", source_tool: "pi", text: "firefox stylix color theme" });
  logPrompt(db, { ts_ms: 20, hostname: "h2", cwd: "/b", session_id: "s2", source_tool: "claude", text: "enable colorTheme option" });
  logPrompt(db, { ts_ms: 30, hostname: "h1", cwd: "/a/proj", session_id: "s3", source_tool: "codex", text: "unrelated note" });
  return db;
}

test("FTS query matches by token, ranked", () => {
  const rows = searchPrompts(seed(), { query: "stylix" });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].source_tool, "pi");
});

test("FTS query tolerates punctuation without throwing", () => {
  const rows = searchPrompts(seed(), { query: 'color "theme"' });
  assert.ok(rows.length >= 1);
});

test("no query returns most recent first", () => {
  const rows = searchPrompts(seed(), {});
  assert.equal(rows[0].ts_ms, 30);
});

test("filters: tool, host, project, since, starred", () => {
  const db = seed();
  assert.equal(searchPrompts(db, { filters: { tool: "claude" } }).length, 1);
  assert.equal(searchPrompts(db, { filters: { host: "h1" } }).length, 2);
  assert.equal(searchPrompts(db, { filters: { project: "proj" } }).length, 2);
  assert.equal(searchPrompts(db, { filters: { since: 25 } }).length, 1);
  const id = searchPrompts(db, { query: "stylix" })[0].id;
  setStar(db, id, true);
  assert.equal(searchPrompts(db, { filters: { starred: true } }).length, 1);
});

test("setTags round-trips and text is never mutated", () => {
  const db = seed();
  const row = searchPrompts(db, { query: "stylix" })[0];
  setTags(db, row.id, "good reusable");
  const after = searchPrompts(db, { query: "stylix" })[0];
  assert.equal(after.tags, "good reusable");
  assert.equal(after.text, row.text);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test`
Expected: FAIL — `searchPrompts is not a function`.

- [ ] **Step 3: Write minimal implementation**

Append to `db.ts`:

```typescript
// Build an FTS5 MATCH string from free text: quote each whitespace token so
// arbitrary user input cannot trigger FTS syntax errors; tokens are implicit-AND.
function ftsQuery(query: string): string {
  return query
    .split(/\s+/)
    .filter(Boolean)
    .map((t) => '"' + t.replace(/"/g, '""') + '"')
    .join(" ");
}

// Translate filters into a WHERE fragment (prefixed with " AND ") + params.
function whereFromFilters(f: SearchFilters): { sql: string; params: (string | number)[] } {
  const clauses: string[] = [];
  const params: (string | number)[] = [];
  if (f.starred) clauses.push("p.starred = 1");
  if (f.host) { clauses.push("p.hostname = ?"); params.push(f.host); }
  if (f.tool) { clauses.push("p.source_tool = ?"); params.push(f.tool); }
  if (f.project) { clauses.push("p.cwd LIKE ?"); params.push("%" + f.project + "%"); }
  if (f.since !== undefined) { clauses.push("p.ts_ms >= ?"); params.push(f.since); }
  return { sql: clauses.length ? " AND " + clauses.join(" AND ") : "", params };
}

// Search prompts. With a query: FTS5 MATCH ranked by relevance. Without: most
// recent first. Filters are applied as SQL WHERE clauses in both paths.
export function searchPrompts(
  db: DatabaseSync,
  opts: { query?: string; filters?: SearchFilters; limit?: number } = {},
): PromptRow[] {
  const where = whereFromFilters(opts.filters ?? {});
  const limit = opts.limit ?? 50;
  const q = (opts.query ?? "").trim();
  if (q) {
    return db
      .prepare(
        `SELECT p.* FROM prompts_fts f
           JOIN prompts p ON p.id = f.rowid
          WHERE prompts_fts MATCH ?${where.sql}
          ORDER BY rank
          LIMIT ?`,
      )
      .all(ftsQuery(q), ...where.params, limit) as unknown as PromptRow[];
  }
  return db
    .prepare(`SELECT p.* FROM prompts p WHERE 1=1${where.sql} ORDER BY p.ts_ms DESC LIMIT ?`)
    .all(...where.params, limit) as unknown as PromptRow[];
}

// Mutable metadata only. There is deliberately no function that updates `text`.
export function setStar(db: DatabaseSync, id: number, starred: boolean): void {
  db.prepare("UPDATE prompts SET starred = ? WHERE id = ?").run(starred ? 1 : 0, id);
}

export function setTags(db: DatabaseSync, id: number, tags: string): void {
  db.prepare("UPDATE prompts SET tags = ? WHERE id = ?").run(tags, id);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test`
Expected: PASS — all db tests green.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/db.ts \
        modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/db.test.ts
git commit -m "feat(prompt-log): searchPrompts (FTS + filters), setStar, setTags"
```

---

### Task 3: history source parsers

**Files:**
- Create: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/sources.ts`
- Create: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/sources.test.ts`

**Interfaces:**
- Consumes: `NewPrompt` from `db.ts`.
- Produces (all return `NewPrompt[]` with `hostname` left unset — the caller adds it):
  - `function parsePiSession(content: string): NewPrompt[]`
  - `function parseClaudeHistory(content: string): NewPrompt[]`
  - `function parseCodexHistory(content: string): NewPrompt[]`

**Reference formats (verified on disk):**
- pi session jsonl: header line `{"type":"session","id":...,"cwd":...,"timestamp":ISO}`, prompts `{"type":"message","timestamp":ISO,"message":{"role":"user","content":[{"type":"text","text":...}]}}`.
- claude `~/.claude/history.jsonl`: `{"display":..,"timestamp":ms,"project":..,"sessionId":..}`.
- codex `~/.codex/history.jsonl`: `{"session_id":..,"ts":seconds,"text":..}`.

- [ ] **Step 1: Write the failing test**

Create `sources.test.ts`:

```typescript
import { test } from "node:test";
import assert from "node:assert";
import { parsePiSession, parseClaudeHistory, parseCodexHistory } from "./sources.ts";

test("parsePiSession extracts user prompts with cwd + session id from header", () => {
  const content = [
    JSON.stringify({ type: "session", id: "sess-1", cwd: "/home/p", timestamp: "2026-06-24T19:09:36.556Z" }),
    JSON.stringify({ type: "model_change", id: "m" }),
    JSON.stringify({ type: "message", timestamp: "2026-06-24T19:12:16.235Z", message: { role: "user", content: [{ type: "text", text: "brainstorm this" }] } }),
    JSON.stringify({ type: "message", timestamp: "2026-06-24T19:13:00.000Z", message: { role: "assistant", content: [{ type: "text", text: "ok" }] } }),
    "",
  ].join("\n");
  const rows = parsePiSession(content);
  assert.equal(rows.length, 1);
  assert.deepEqual(
    { text: rows[0].text, cwd: rows[0].cwd, session_id: rows[0].session_id, source_tool: rows[0].source_tool },
    { text: "brainstorm this", cwd: "/home/p", session_id: "sess-1", source_tool: "pi" },
  );
  assert.equal(rows[0].ts_ms, Date.parse("2026-06-24T19:12:16.235Z"));
});

test("parsePiSession skips malformed lines and empty user text", () => {
  const content = [
    "not json",
    JSON.stringify({ type: "message", timestamp: "2026-06-24T00:00:00.000Z", message: { role: "user", content: [] } }),
  ].join("\n");
  assert.equal(parsePiSession(content).length, 0);
});

test("parseClaudeHistory maps display/timestamp/project/sessionId", () => {
  const content = JSON.stringify({ display: "enable colorTheme", timestamp: 1778854334387, project: "/home/felix/projects/dotfiles", sessionId: "c-1" });
  const rows = parseClaudeHistory(content);
  assert.equal(rows.length, 1);
  assert.deepEqual(
    { text: rows[0].text, ts_ms: rows[0].ts_ms, cwd: rows[0].cwd, session_id: rows[0].session_id, source_tool: rows[0].source_tool },
    { text: "enable colorTheme", ts_ms: 1778854334387, cwd: "/home/felix/projects/dotfiles", session_id: "c-1", source_tool: "claude" },
  );
});

test("parseCodexHistory maps text/ts(sec->ms)/session_id, cwd null", () => {
  const content = JSON.stringify({ session_id: "x-1", ts: 1775120367, text: "continue" });
  const rows = parseCodexHistory(content);
  assert.equal(rows.length, 1);
  assert.deepEqual(
    { text: rows[0].text, ts_ms: rows[0].ts_ms, cwd: rows[0].cwd, session_id: rows[0].session_id, source_tool: rows[0].source_tool },
    { text: "continue", ts_ms: 1775120367000, cwd: null, session_id: "x-1", source_tool: "codex" },
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test`
Expected: FAIL — `Cannot find module './sources.ts'`.

- [ ] **Step 3: Write minimal implementation**

Create `sources.ts`:

```typescript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test`
Expected: PASS — all source + db tests green.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/sources.ts \
        modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/sources.test.ts
git commit -m "feat(prompt-log): pure history parsers for pi/claude/codex"
```

---

### Task 4: backfill CLI

**Files:**
- Create: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/import.ts`
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/sources.test.ts` (append an end-to-end ingest test)

**Interfaces:**
- Consumes: `openDb`, `logPrompt`, `NewPrompt` (db.ts); the three parsers (sources.ts).
- Produces:
  - `function piSessionFiles(dir: string): string[]` — recursive `*.jsonl`, skipping `subagents/`
  - `function ingest(db: DatabaseSync, rows: NewPrompt[]): { read: number; inserted: number }` — adds current `hostname` to each row
  - `function main(): void` — opens `~/.pi/agent/prompts.db`, ingests all three sources, prints a per-source summary, closes the DB
  - Runs `main()` only when invoked directly (`node import.ts`), not when imported.

- [ ] **Step 1: Write the failing test**

Append to `sources.test.ts`:

```typescript
import { ingest } from "./import.ts";
import { openDb, searchPrompts } from "./db.ts";

test("ingest inserts parsed rows with hostname and dedups on re-run", () => {
  const db = openDb(":memory:");
  const rows = parseCodexHistory(
    [JSON.stringify({ session_id: "x", ts: 1, text: "alpha" }), JSON.stringify({ session_id: "x", ts: 2, text: "beta" })].join("\n"),
  );
  const first = ingest(db, rows);
  assert.deepEqual(first, { read: 2, inserted: 2 });
  const second = ingest(db, rows); // idempotent
  assert.deepEqual(second, { read: 2, inserted: 0 });
  const all = searchPrompts(db, {});
  assert.equal(all.length, 2);
  assert.ok(all[0].hostname && all[0].hostname.length > 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test`
Expected: FAIL — `Cannot find module './import.ts'` / `ingest is not a function`.

- [ ] **Step 3: Write minimal implementation**

Create `import.ts`:

```typescript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test`
Expected: PASS — ingest test green, nothing else regressed.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/import.ts \
        modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/sources.test.ts
git commit -m "feat(prompt-log): idempotent backfill CLI for pi/claude/codex history"
```

---

### Task 5: pi extension — live logging + /prompts command

**Files:**
- Create: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/index.ts`
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/sources.test.ts` (append parseArgs/fmtRow unit tests)

**Interfaces:**
- Consumes: `openDb`, `logPrompt`, `searchPrompts`, `setStar`, `setTags`, `PromptRow`, `SearchFilters` (db.ts); pi `ExtensionAPI`, `ExtensionContext`.
- Produces (exported for unit testing):
  - `function parseArgs(args: string): { query: string; filters: SearchFilters }`
  - `function fmtRow(r: PromptRow): string`
  - `default function (pi: ExtensionAPI): void` — the extension factory

- [ ] **Step 1: Write the failing test**

Append to `sources.test.ts`:

```typescript
import { parseArgs, fmtRow } from "./index.ts";

test("parseArgs splits flags from free-text query", () => {
  const { query, filters } = parseArgs("--starred --tool pi --project dotfiles stylix theme");
  assert.equal(query, "stylix theme");
  assert.equal(filters.starred, true);
  assert.equal(filters.tool, "pi");
  assert.equal(filters.project, "dotfiles");
});

test("parseArgs --since parses a date to ms; bad date ignored", () => {
  assert.equal(parseArgs("--since 2026-06-01 x").filters.since, Date.parse("2026-06-01"));
  assert.equal(parseArgs("--since notadate x").filters.since, undefined);
});

test("fmtRow shows star, tool, date prefix and unique id", () => {
  const row = { id: 7, ts_ms: Date.parse("2026-06-24T10:00:00Z"), hostname: "h", cwd: "/p", session_id: "s", source_tool: "pi", source: "interactive", text: "firefox\n  stylix   color", starred: 1, tags: null } as any;
  const s = fmtRow(row);
  assert.match(s, /★/);
  assert.match(s, /\[pi\]/);
  assert.match(s, /2026-06-24/);
  assert.match(s, /#7/);
  assert.ok(!s.includes("\n"));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test`
Expected: FAIL — `Cannot find module './index.ts'` / `parseArgs is not a function`.

> Note: importing `index.ts` only pulls in the exported `parseArgs`/`fmtRow`; the `default` factory is not invoked by the import, so no pi runtime is needed for these tests.

- [ ] **Step 3: Write minimal implementation**

Create `index.ts`:

```typescript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test`
Expected: PASS — parseArgs/fmtRow tests green; full suite green.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/index.ts \
        modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/sources.test.ts
git commit -m "feat(prompt-log): pi extension with live logging and /prompts command"
```

---

### Task 6: deploy, backfill, and verify end-to-end

**Files:**
- Verify only: `modules/home-manager/profiles/ai-agents/pi-extensions.nix` (already auto-symlinks subdirs with `index.ts` — no edit expected).

- [ ] **Step 1: Confirm nix will symlink the new extension dir**

Run: `grep -n 'index.ts' modules/home-manager/profiles/ai-agents/pi-extensions.nix`
Expected: the `subdirs` branch matches directories containing `index.ts`. No change needed. (If it is missing, that is a separate bug — stop and report.)

- [ ] **Step 2: Build the home-manager generation (no activation)**

Run: `nixos-rebuild build 2>&1 | tail -5`
Expected: builds without evaluation errors. (Per project rules, do NOT run `nrs`/switch — the user activates manually.)

- [ ] **Step 3: Ask the user to switch + reload**

Tell the user:
> Run your normal `nrs` (same specialization) to activate, then in a pi session run `/reload`. The `/prompts` command should then be available.

Wait for confirmation that `~/.pi/agent/extensions/prompt-log/index.ts` is symlinked and `/reload` succeeded.

- [ ] **Step 4: Run the one-time backfill**

Run: `node ~/.pi/agent/extensions/prompt-log/import.ts`
Expected: three summary lines, e.g. `pi: read N, inserted N, skipped 0` / `claude: ...` / `codex: ...`. Re-running should show `inserted 0` everywhere (idempotent).

- [ ] **Step 5: Verify the DB and FTS**

Run:
```bash
nix-shell -p sqlite --run "sqlite3 ~/.pi/agent/prompts.db \
  'SELECT source_tool, COUNT(*) FROM prompts GROUP BY source_tool;
   SELECT id, source_tool, substr(text,1,50) FROM prompts_fts JOIN prompts ON prompts.id=prompts_fts.rowid WHERE prompts_fts MATCH \"stylix\" LIMIT 3;'"
```
Expected: per-tool counts > 0 and at least one FTS hit. Confirms the corpus imported and search works from any external tool.

- [ ] **Step 6: Manual in-pi verification**

In a pi session:
1. Type a prompt, then `/prompts` (no args) — the just-typed prompt appears at the top (live logging works).
2. `/prompts stylix` — FTS results appear; pick one → "Recall to editor" loads its text into the editor.
3. `/prompts` → pick one → "Star"; then `/prompts --starred` shows it.
4. `/prompts` → pick one → "Edit tags", enter `good reusable`; re-open and confirm the tag persisted.

- [ ] **Step 7: Commit (if nix needed any change)**

Only if Step 1 required editing `pi-extensions.nix`:
```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions.nix
git commit -m "feat(prompt-log): wire prompt-log extension into pi-extensions"
```
Otherwise nothing to commit here — deployment uses the existing auto-discovery.

---

## Notes for the implementer

- **ExperimentalWarning:** `node:sqlite` prints `ExperimentalWarning` to stderr on every run. This is expected and harmless; tests still pass.
- **No `package.json`:** do not add one. All imports are Node builtins or pi-provided. Adding deps would trigger an `npm install` requirement the design deliberately avoids.
- **Why `import.ts` is not loaded by pi:** the nix symlinker links the whole dir but pi only loads `index.ts`; `import.ts`, `db.ts`, `sources.ts`, and `*.test.ts` are imported by `index.ts`/tests or run manually, never auto-loaded as extensions.
- **devLinks (optional):** to iterate without a full switch, add `modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log` to `my.devLinks`, then edits in the working tree are live after `/reload`.
```
