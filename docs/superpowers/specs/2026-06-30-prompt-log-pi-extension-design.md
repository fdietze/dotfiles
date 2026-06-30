# prompt-log: searchable sqlite log of every user prompt

## Problem

Every prompt I type into pi is already persisted — but scattered across per-project
session jsonl files (`~/.pi/agent/sessions/<project>/*.jsonl`), interleaved with
assistant/tool/thinking entries. No unified, queryable corpus. Same story for prior
tools (Claude Code, Codex) which keep their own history files. I want one searchable
store of every prompt I have ever typed, across pi/claude/codex, that I can recall
from — but never accidentally edit.

## Goal

A pi extension `prompt-log` that:
1. logs every interactive prompt I type into pi, live, into one global sqlite DB
2. backfills all historical prompts from pi, Claude Code, and Codex (one-time)
3. lets me full-text search and recall a past prompt back into the editor
4. lets me star/tag prompts to curate a reusable library
5. guarantees prompt text is write-once (search, never edit)

## Non-goals

- No editing or deletion of prompt text (immutable by construction).
- No syncing across machines (single local DB; `hostname` column kept for future).
- No capturing of assistant output, tool calls, or non-interactive (rpc/extension) input.
- No markdown export / second source of truth (DB is the single asset).

## Decisions (from brainstorm)

- **Scope (Q1=B):** log interactive prompts only (`source === "interactive"`),
  including raw `/cmd` and `!cmd` text. Exclude rpc/extension-injected input.
- **Location (Q2=A):** one global DB `~/.pi/agent/prompts.db`, project as a column.
- **Search (Q3=C):** FTS5 DB is the real asset (any external tool works) +
  a thin in-pi `/prompts` command for fast recall.
- **Mark action (Q4=B):** star + recall-to-editor. Star alone is a graveyard;
  recall makes the star a re-runnable library.
- **Flag UX (Q5):** two-step built-in `ctx.ui.select` menus, no custom TUI component.
- **Backfill (Q6=A + note):** one-time importer over pi + `~/.claude` + `~/.codex`,
  then live logging. Importer is idempotent (re-runnable).
- **Dedup (Q7=A):** `UNIQUE(source_tool, session_id, text)` — drop ts from the key so
  live + re-import of the same prompt collapse despite ms drift. Keeps earliest ts.

## Architecture

Directory-style extension (nix symlinks the dir; pi loads only `index.ts`,
`import.ts` stays inert):

```
modules/home-manager/profiles/ai-agents/pi-extensions/prompt-log/
├── index.ts    # live logging (input event) + /prompts command
├── import.ts   # one-time backfill, run via `node import.ts`
└── db.ts       # shared: open DB, schema/migrations, insert, search, star, tag
```

Zero npm deps: `node:sqlite`, `node:os`, `node:fs`, `node:path`, `node:readline`
are all builtins (Node 24 runs `.ts` natively). KISS.

### Functional core / imperative shell

- `db.ts` is the functional-ish core: pure-ish DB operations behind small named
  functions (`openDb`, `logPrompt`, `searchPrompts`, `setStar`, `setTags`). No pi
  imports. Testable standalone and reused by both `index.ts` and `import.ts` (DRY).
- `index.ts` / `import.ts` are the imperative shells (pi events, file walking, CLI).

## Data model

DB `~/.pi/agent/prompts.db`, opened with `PRAGMA journal_mode=WAL` and
`PRAGMA busy_timeout=5000` — multiple concurrent pi instances write to it.

```sql
CREATE TABLE IF NOT EXISTS prompts (
  id          INTEGER PRIMARY KEY,
  ts_ms       INTEGER NOT NULL,   -- epoch ms (earliest seen wins on dedup)
  hostname    TEXT,               -- os.hostname() at insert; importer uses current host
  cwd         TEXT,               -- project dir; NULL for codex (no project field)
  session_id  TEXT,
  source_tool TEXT NOT NULL,      -- 'pi' | 'claude' | 'codex'
  source      TEXT,               -- 'interactive' (live) | source tool (import)
  text        TEXT NOT NULL,      -- WRITE-ONCE: never UPDATEd/DELETEd
  starred     INTEGER NOT NULL DEFAULT 0,  -- mutable metadata
  tags        TEXT,                         -- mutable, space-separated freeform
  UNIQUE(source_tool, session_id, text)     -- idempotent re-import + no double-log
);

-- full-text index over prompt text, kept in sync by an insert trigger only
CREATE VIRTUAL TABLE IF NOT EXISTS prompts_fts
  USING fts5(text, content='prompts', content_rowid='id');

CREATE TRIGGER IF NOT EXISTS prompts_ai AFTER INSERT ON prompts BEGIN
  INSERT INTO prompts_fts(rowid, text) VALUES (new.id, new.text);
END;
```

No update/delete triggers exist because `text` is immutable; `starred`/`tags` are not
indexed. Inserts use `INSERT OR IGNORE` so the UNIQUE constraint silently dedups.

**Immutability guarantee:** the only UPDATE statements in the codebase touch
`starred` and `tags`. No statement ever updates or deletes `text`. This is the
structural enforcement of "search but not edit old prompts."

## Live logging (index.ts)

```
pi.on("input", (event, ctx) => {
  if (event.source !== "interactive") return;        // skip rpc/extension noise
  logPrompt(db, {
    ts_ms: Date.now(),
    hostname: os.hostname(),
    cwd: ctx.cwd,
    session_id: <current session id from ctx.sessionManager>,
    source_tool: "pi",
    source: "interactive",
    text: event.text,                                 // raw, incl. /cmd and !cmd
  });
  // return nothing -> { action: "continue" }, never blocks/transforms input
});
```

DB opened lazily on first `session_start` (per extension lifecycle guidance: no
background resources from the factory). Closed on `session_shutdown`.

## /prompts command (index.ts)

`/prompts [query] [filters]`

1. Parse filters: `--starred`, `--host <h>`, `--project <p>`, `--tool <pi|claude|codex>`,
   `--since <YYYY-MM-DD>`. Remaining words = FTS query (empty → recent prompts).
2. `searchPrompts(db, {query, filters, limit})` → rows (FTS5 MATCH when query given,
   ranked by relevance; else most recent first), filters applied as SQL WHERE.
3. `ctx.ui.select` list: each row rendered as `★? [tool] date — first ~80 chars`.
4. On pick → second `ctx.ui.select` action menu:
   - **Recall to editor** → `ctx.ui.setEditorText(row.text)` (the reuse payoff)
   - **Toggle star** → `setStar(db, id, !starred)`
   - **Add/replace tags** → `ctx.ui.input(...)` → `setTags(db, id, value)`
5. Guard with `ctx.hasUI`; command only runs in TUI/RPC.

## Importer (import.ts)

Run once: `node ~/.pi/agent/extensions/prompt-log/import.ts`. Idempotent — safe to
re-run (INSERT OR IGNORE). Walks three sources, normalizes to the row shape, inserts:

| Source | Path | Fields → row |
|--------|------|--------------|
| pi | `~/.pi/agent/sessions/**/*.jsonl` | `message.role==="user"` text entries; `ts_ms` from entry timestamp, `cwd` from the `session` header line, `session_id` from header `id`; `source_tool='pi'` |
| claude | `~/.claude/history.jsonl` | `{display→text, timestamp→ts_ms, project→cwd, sessionId→session_id}`; `source_tool='claude'` |
| codex | `~/.codex/history.jsonl` | `{text, ts(sec)*1000→ts_ms, session_id, cwd=NULL}`; `source_tool='codex'` |

`hostname` = `os.hostname()` for all imported rows (all history is from this machine).
`source` = the tool name for imports (vs `'interactive'` for live).
Prints a summary: per-source rows read / inserted / skipped-as-duplicate.

## Concurrency & failure handling

- WAL + `busy_timeout=5000` handles concurrent pi instances.
- Live `logPrompt` wrapped in try/catch that never throws into the input pipeline —
  a logging failure must not block me from sending a prompt. Logs a one-line warning.
- Importer is read-only against source files; only writes to `prompts.db`.

## Testing

- `db.ts` unit-testable with an in-memory / temp-file DB: insert + dedup
  (same `(source_tool, session_id, text)` collapses, earliest ts kept), FTS search
  hits, star/tag round-trip, and that no API mutates `text`.
- Importer: feed small fixture jsonl for each of the 3 formats, assert normalized rows
  and idempotency on second run.
- Live logging: assert non-interactive sources are skipped.

## Deployment

1. Add the `prompt-log/` dir under `pi-extensions/`; `pi-extensions.nix` auto-symlinks
   it (directory + `index.ts` branch already handles this).
2. Home-Manager switch, then `/reload` in pi.
3. Run the importer once for backfill.
4. Optionally add `relRoot/prompt-log` to `my.devLinks` for out-of-store live editing.
