---
name: triage-and-commit
description: Use when a git repo has many uncommitted changes of mixed/unknown status and the user wants to commit only the ones they confirm are working, leaving everything else untouched. Triggers include "kraut und rüben", "mess", "triage", "sort out", "cherry-pick what works", "only commit what works".
---

# Triage And Commit

## Overview

The working tree is a mess: many unrelated edits, some working, some experimental, some half-broken. The user wants to commit ONLY items they explicitly confirm as working, in logical commits, and leave everything else uncommitted.

**Core rule:** Nothing the user did not explicitly confirm gets committed. Silence ≠ consent.

## When to Use

- User says some variation of: "lots of uncommitted changes, I don't know what works, help me sort it out"
- `git status` shows many unrelated modifications / untracked files
- User wants selective commits based on their feedback
- User mentions "kraut und rüben", "mess", "triage", "sort out", "cherry-pick what works"

**Do NOT use when:**
- User just says "commit everything" / "commit my changes" (use normal commit flow)
- Changes are clearly one logical unit
- User already knows what they want committed

## Workflow

```
1. Inventory   →  2. Group into items   →  3. Run auto-checks   →  4. Present numbered list
                                                                              ↓
7. Commit confirmed   ←   6. Plan commits   ←   5. Wait for user feedback
```

### Step 1: Inventory

Run in parallel:
- `git status` (no `-uall`)
- `git diff` (unstaged)
- `git diff --staged` (staged, if any)
- `git log -10 --oneline` (to match commit style)

For untracked files or large diffs, read the actual file contents to understand what they do — do not guess from filenames alone.

### Step 2: Group into Logical Items

Bundle related changes into independent, commit-sized "items". A single item may touch multiple files (e.g. a feature + its config + its generated output). Different items must be independently committable.

Heuristics:
- Same feature/topic → one item
- Generated/build artifacts go with the source that produced them
- Config edits unrelated to code edits → separate item
- A new tool/script + its packaging files → one item
- Unrelated tweaks → separate items

Aim for items that map to ~one good commit each.

### Step 3: Determine Verification per Item

For each item, decide how to verify it works:

- **`auto:`** — a concrete command you can run yourself. Examples by ecosystem:
  - Build: `cargo build`, `go build ./...`, `npm run build`, `tsc --noEmit`, `mvn compile`
  - Test: `cargo test`, `go test ./...`, `npm test`, `pytest`, `mix test`
  - Lint/format: `ruff check`, `eslint`, `gofmt -l`, `cargo clippy`
  - Type check: `mypy`, `tsc --noEmit`, `pyright`
  - Project-specific: `nix flake check`, `nixos-rebuild build`, `terraform validate`, `docker build`
  - Dry-run / syntax: `bash -n script.sh`, `python -m py_compile file.py`, `nix-instantiate --parse`
- **`user:`** — a concrete action the user must take when no automatic check exists. Be specific: "open <app> and check <X>", "run `<cmd>` and confirm <Y>", "trigger <action> and verify <observable>".

**Run all `auto:` checks BEFORE presenting the list**, so the user sees PASS/FAIL up front. If an auto check fails, still list the item but mark it `auto: FAIL — <reason>` so the user can decide whether to investigate or skip.

Inspect the repo to discover the right commands (look at `Makefile`, `package.json` scripts, `flake.nix`, `pyproject.toml`, `Cargo.toml`, CI configs). Don't invent commands — only use ones that actually exist in this project.

### Step 4: Present the List

Show a **numbered list**. For each item:
- Short title (what it is)
- Files touched (concise)
- One sentence on what changed / what it does
- `auto:` result (or "none applicable")
- `user:` action (or "none needed if auto passes")

Match the user's language (if they wrote German, reply in German; same for any other language).

**Example format (generic):**

```
1. Add retry logic to HTTP client
   src/http/client.{ts,test.ts}
   Wraps fetch in exponential-backoff retry up to 3 attempts.
   auto: `npm test -- src/http` — PASS
   user: none needed if auto passes

2. New CLI flag --verbose
   src/cli.ts, README.md
   Adds --verbose flag that enables debug logging.
   auto: `npm run build` — PASS; no test coverage for this path
   user: run `./bin/foo --verbose` and confirm debug output appears

3. Bump dependency lockfile
   package-lock.json
   Routine lockfile update from `npm install`.
   auto: `npm test` — PASS
   user: none needed if auto passes
```

Then ask: "Which of these work for you? Tell me the numbers (or describe in your own words). Anything not mentioned stays uncommitted."

### Step 5: Wait for Feedback

**Stop here. Do not commit yet.** Wait for the user's reply.

If the user confirms items vaguely ("1, 2, the retry thing works"), restate exactly what you'll commit before proceeding.

### Step 6: Plan Commits

For each confirmed item:
- Decide commit message (match repo style from `git log`)
- Decide which exact files/hunks to stage
- If an item spans both modified and untracked files, both must be staged
- If a file has changes belonging to MULTIPLE items (some confirmed, some not), use `git add -p` for hunk-level staging — never stage the whole file

### Step 7: Commit

For each confirmed item, sequentially:
1. `git add <specific files>` (never `git add -A` or `git add .`)
2. `git diff --staged` to verify only intended changes are staged
3. `git commit -m "..."`
4. `git status` to confirm the rest is still untouched

After all commits: show final `git status` so the user can see what remains uncommitted.

## Hard Rules

- **Never** `git add -A`, `git add .`, or `git add -u`. Always name files explicitly.
- **Never** commit an item the user did not explicitly mention as working.
- **Never** stash, reset, or discard the unmentioned changes. They stay in the working tree exactly as they were.
- **Never** amend or rebase as part of this flow.
- **Never** invent verification commands — only use ones that exist in the repo's tooling.
- If a file's diff mixes confirmed and unconfirmed changes, use `git add -p`. If hunks can't be cleanly separated, ask the user.
- If unsure whether a change belongs to a confirmed item, ASK — do not assume.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Grouping unrelated changes because they touch the same file | Use `git add -p` to split by hunk |
| Committing the "obvious safe stuff" (lockfile, formatting) without asking | Everything needs explicit confirmation |
| Inferring intent from filenames without reading diffs | Read the diff before grouping |
| Skipping the verification `git diff --staged` between add and commit | Always verify staged content before committing |
| Presenting items in a wall of prose instead of a numbered list | Numbered list, one block per item, scannable |
| Skipping auto-checks because "the diff looks fine" | Run the checks. The diff doesn't run the code. |
| Inventing build/test commands not used by this project | Inspect Makefile / package.json / flake.nix etc. first |

## Red Flags — STOP

- About to run `git add -A` → STOP, stage explicitly
- About to commit without user having confirmed that specific item → STOP
- User said "looks good" but you bundled in an item they didn't mention → STOP, ask
- Tempted to "clean up" or "tidy" unmentioned changes → STOP, leave them alone
- Presenting the list without having run available auto-checks → STOP, run them first
