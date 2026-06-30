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
