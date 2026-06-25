# OSC 52 clipboard for zsh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `zsh-system-clipboard` with a terminal-agnostic OSC 52 clipboard mechanism so yank/paste sync to the local clipboard over ssh on headless hosts.

**Architecture:** One repo-local `zsh-osc52-clipboard.zsh` provides `osc52-copy` (write, args-or-stdin → base64 → `ESC]52` to `/dev/tty`, tmux/screen passthrough) and `osc52-paste` (query + raw-read `/dev/tty` → decode → stdout). ZLE overrides the same builtin vi widget names so existing keybindings auto-pick-up. Inlined into `programs.zsh.initContent` via `builtins.readFile`; shared by every host through `shell.nix`.

**Tech Stack:** zsh ZLE widgets, coreutils `base64`, home-manager, OSC 52 escape sequences.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-25-osc52-clipboard-design.md`.
- `osc52-copy` is the single authoritative clipboard-write (used by ZLE copy widgets AND the `C` global alias) — DRY.
- Essentials-only ZLE coverage, `vicmd` + `visual`: copy widgets `vi-yank`, `vi-yank-whole-line`, `vi-delete`, `vi-delete-char`, `vi-backward-delete-char`, `vi-change`; paste widgets `vi-put-after`, `vi-put-before`.
- File written at runtime by nix (home-manager); the `.zsh` source is hand-maintained in-repo — add a header comment explaining purpose + caveats.
- Never run system-activating rebuilds. `home-manager build` (no activation) only; user activates manually.
- Comments document why, referring only to current code.

---

### Task 1: The `zsh-osc52-clipboard.zsh` file

**Files:**
- Create: `modules/home-manager/zsh-osc52-clipboard.zsh`
- Test: `modules/home-manager/zsh-osc52-clipboard.test.zsh`

**Interfaces:**
- Produces: shell functions `osc52-copy` (reads `"$*"` or stdin; honors `OSC52_OUT` env, default `/dev/tty`, for test capture) and `osc52-paste` (clipboard → stdout). ZLE widgets rebind builtin names listed in Global Constraints.

**Testability seam:** `osc52-copy` writes to `${OSC52_OUT:-/dev/tty}` so tests can capture the emitted bytes by setting `OSC52_OUT=/dev/stdout`. This is the only concession to testing; `osc52-paste` needs a real responding tty and is verified interactively in Task 3.

- [ ] **Step 1: Write the failing test**

Create `modules/home-manager/zsh-osc52-clipboard.test.zsh`:

```zsh
#!/usr/bin/env zsh
# Unit test for osc52-copy byte output (encoding + multiplexer wrapping).
# osc52-paste and ZLE widgets need a real tty and are verified interactively.
set -e
SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/zsh-osc52-clipboard.zsh"

fail() { print -u2 "FAIL: $1"; exit 1; }

# base64("hello") = aGVsbG8=
expected=$'\e]52;c;aGVsbG8=\a'

# arg input, no multiplexer
got=$(TMUX= STY= OSC52_OUT=/dev/stdout osc52-copy hello)
[[ "$got" == "$expected" ]] || fail "arg input: got ${(q)got}"

# stdin input
got=$(TMUX= STY= OSC52_OUT=/dev/stdout print -rn -- hello | OSC52_OUT=/dev/stdout TMUX= STY= osc52-copy)
[[ "$got" == "$expected" ]] || fail "stdin input: got ${(q)got}"

# tmux passthrough wraps in ESC P tmux; ... ESC backslash with ESC doubled
tmux_expected=$'\ePtmux;\e\e]52;c;aGVsbG8=\a\e\\'
got=$(TMUX=/tmp/x,0,0 STY= OSC52_OUT=/dev/stdout osc52-copy hello)
[[ "$got" == "$tmux_expected" ]] || fail "tmux wrap: got ${(q)got}"

print "PASS"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd modules/home-manager && nix-shell -p zsh coreutils --run 'zsh zsh-osc52-clipboard.test.zsh'`
Expected: FAIL — file `zsh-osc52-clipboard.zsh` does not exist (source error).

- [ ] **Step 3: Write minimal implementation**

Create `modules/home-manager/zsh-osc52-clipboard.zsh`:

```zsh
# OSC 52 clipboard sync for zsh. Replaces zsh-system-clipboard so yank/paste
# reach the LOCAL clipboard over ssh without any remote clipboard manager
# (no wl-copy/xclip/xsel, no $DISPLAY). OSC 52 is a terminal escape the local
# terminal intercepts; it rides the tty stream through ssh.
#
# Caveats:
# - Copy escapes tmux/screen via DCS passthrough. Read (p) does NOT reliably
#   traverse tmux/screen (they don't proxy OSC 52 read-back). Bare ssh works.
# - Needs a terminal that allows silent read-clipboard (kitty/ghostty are
#   configured for it in shared.nix); other terminals are copy-only.

# Single authoritative clipboard write. Input: "$*" if args, else stdin.
# Output target is overridable (OSC52_OUT) only so the unit test can capture
# the bytes; interactively it is /dev/tty.
osc52-copy() {
  local data b64
  if (( $# )); then
    data="$*"
  else
    data="$(cat)"
  fi
  b64=$(printf '%s' "$data" | base64 | tr -d '\n')
  local seq=$'\e]52;c;'"$b64"$'\a'
  # tmux/screen need the escape wrapped in DCS passthrough, ESC doubled, so the
  # multiplexer forwards it to the outer terminal instead of swallowing it.
  if [[ -n "$TMUX" ]]; then
    seq=$'\ePtmux;'"${seq//$'\e'/$'\e\e'}"$'\e\\'
  elif [[ -n "$STY" ]]; then
    seq=$'\eP'"${seq//$'\e'/$'\e\e'}"$'\e\\'
  fi
  printf '%s' "$seq" > "${OSC52_OUT:-/dev/tty}"
}

# Clipboard read -> stdout. Queries the terminal and parses its OSC 52 reply.
osc52-paste() {
  local old reply
  old=$(stty -g </dev/tty)
  trap 'stty "$old" </dev/tty' EXIT INT TERM
  stty raw -echo </dev/tty
  printf '\e]52;c;?\a' > /dev/tty
  # Reply: ESC ] 52 ; c ; <base64> (BEL | ESC backslash). Read until BEL.
  IFS= read -r -t 1 -d $'\a' reply </dev/tty || true
  stty "$old" </dev/tty
  trap - EXIT INT TERM
  # Strip everything up to the last "52;c;" then base64-decode.
  reply=${reply##*52;c;}
  [[ -n "$reply" ]] && printf '%s' "$reply" | base64 -d 2>/dev/null
}

# ZLE: override the builtin vi widget names so existing keybindings pick these
# up automatically (no manual bindkey). Copy widgets sync $CUTBUFFER out after
# running; paste widgets pull the system clipboard into CUTBUFFER first.
if [[ -o zle || -n "$ZSH_VERSION" ]]; then
  local _w
  for _w in vi-yank vi-yank-whole-line vi-delete vi-delete-char \
            vi-backward-delete-char vi-change; do
    eval "_osc52_$_w() { zle .$_w; osc52-copy \"\$CUTBUFFER\" }"
    zle -N "$_w" "_osc52_$_w"
  done
  for _w in vi-put-after vi-put-before; do
    eval "_osc52_$_w() { CUTBUFFER=\$(osc52-paste); zle .$_w }"
    zle -N "$_w" "_osc52_$_w"
  done
  unset _w
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd modules/home-manager && nix-shell -p zsh coreutils --run 'zsh zsh-osc52-clipboard.test.zsh'`
Expected: `PASS`

Note: the `zle -N` block runs at source time outside an interactive shell. In the test, `zle` is not a command in a non-interactive shell, so guard it: the `[[ -o zle ... ]]` test is true under `zsh` but `zle -N` errors when ZLE isn't active. If the test errors on `zle`, wrap the loop body so `zle -N` failures are tolerated in non-interactive context: change the guard to `if zle -N 2>/dev/null; then`-style probe, OR source under `emulate`. Simplest: in the test, the functions are defined before the ZLE block, and a `zle` failure prints to stderr but `set -e` would abort — so prepend the ZLE block with `whence zle >/dev/null 2>&1 &&` is wrong (zle is a builtin/keyword). Instead guard with `[[ -n ${WIDGET+x} || -o zle ]]`. **Resolution:** replace the guard condition with a check that only true interactive ZLE satisfies:

```zsh
# Only register widgets when ZLE is actually available (interactive shell).
if zle -l >/dev/null 2>&1; then
```

Re-run the test; expect `PASS` (the widget block is skipped in the non-interactive test, the two functions still defined).

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/zsh-osc52-clipboard.zsh modules/home-manager/zsh-osc52-clipboard.test.zsh
git commit -m "feat(shell): add OSC 52 clipboard functions + widgets"
```

---

### Task 2: Wire into shell.nix, drop the plugin

**Files:**
- Modify: `modules/home-manager/shell.nix` (plugins list ~line 324; `shellGlobalAliases` `C` ~line 114; `initContent` ~line 118)

**Interfaces:**
- Consumes: `osc52-copy` from Task 1 (the `C` alias targets it).

- [ ] **Step 1: Remove the zsh-system-clipboard plugin entry**

In `modules/home-manager/shell.nix`, delete the plugins entry:

```nix
      {
        name = "zsh-system-clipboard";
        src = pkgs.zsh-system-clipboard;
        file = "share/zsh/zsh-system-clipboard/zsh-system-clipboard.zsh";
      }
```

- [ ] **Step 2: Point the `C` global alias at osc52-copy**

Change:

```nix
      C = "| xclip -selection clipboard";
```
to
```nix
      # OSC 52 clipboard write (works over ssh, no clipboard manager needed).
      C = "| osc52-copy";
```

- [ ] **Step 3: Inline the .zsh file into initContent**

Append to the `initContent` string (after the existing body, before its closing `''`):

```nix
      # OSC 52 clipboard (osc52-copy/osc52-paste + vi widgets); see
      # zsh-osc52-clipboard.zsh. Replaces the old zsh-system-clipboard plugin.
      ${builtins.readFile ./zsh-osc52-clipboard.zsh}
```

- [ ] **Step 4: Build to verify the config evaluates**

Run: `home-manager build --flake .#cubie`
Expected: builds without error.

- [ ] **Step 5: Verify the generated zshrc has the functions and not the plugin**

Run:
```bash
out=$(home-manager build --flake .#cubie --no-link --print-out-paths 2>/dev/null)
zgrep -l . >/dev/null 2>&1; grep -rl "osc52-copy" "$out"/home-path/etc/profile.d 2>/dev/null; \
  find "$out" -name '.zshrc' -exec grep -l "osc52-copy" {} \; ; \
  find "$out" -name '.zshrc' -exec grep -L "zsh-system-clipboard" {} \;
```
Expected: the `.zshrc` contains `osc52-copy` and does NOT contain `zsh-system-clipboard`. (If `home-path` layout differs, just `grep -rn osc52-copy "$out"` and confirm presence; `grep -rn zsh-system-clipboard "$out"` confirms absence.)

- [ ] **Step 6: Commit**

```bash
git add modules/home-manager/shell.nix
git commit -m "feat(shell): replace zsh-system-clipboard with OSC 52, C alias to osc52-copy"
```

---

### Task 3: Interactive verification (no automation)

**Files:** none (manual checklist; user activates).

This task is gated on the user running activation (`home-manager switch`) — agents never activate. Present the checklist and wait for the user's results.

- [ ] **Step 1: Local desktop (kitty) checklist**

After the user activates on a desktop host:
- New zsh: no `zsh-system-clipboard` startup error.
- Type a line, `Esc` then `yy`; switch to another app, paste → the line appears.
- `echo hi | C`; paste elsewhere → `hi`.
- Put something on the system clipboard from another app; in zsh `Esc` then `p` → it inserts into the line buffer.

- [ ] **Step 2: Remote (ssh cubie in kitty) checklist**

After `home-manager switch --flake ~/projects/dotfiles#cubie` on cubie:
- `ssh cubie`: no clipboard error on shell init.
- `yy` on a line → local Ctrl-Shift-V pastes it.
- `echo hi | C` → local clipboard has `hi`.
- `Esc` then `p` → local clipboard contents inserted.

- [ ] **Step 3: tmux exploration (follow-up)**

Inside `tmux` on cubie over ssh:
- Confirm copy still works (DCS passthrough). If not, check tmux `set-clipboard on` and `allow-passthrough on`.
- Test `p` (read). Expected weak/failing per spec caveat. If it fails, evaluate a `tmux show-buffer` fallback inside `osc52-paste` when `$TMUX` is set — but only add it if the gap is real in practice (YAGNI). Capture findings; decide whether a follow-up change is warranted.

---

## Self-Review

**Spec coverage:** mechanism (osc52-copy/paste) → Task 1; ZLE essentials → Task 1; wiring (drop plugin, readFile, C alias) → Task 2; caveats documented in file header → Task 1 Step 3; verification incl. tmux → Task 3. All spec sections covered.

**Placeholders:** none — full file content and exact nix edits provided. Task 3 is explicitly a manual checklist (activation is user-only per AGENTS.md), not a hidden TODO.

**Type consistency:** function names `osc52-copy`/`osc52-paste`, env seam `OSC52_OUT`, and the widget name list are identical across spec, Task 1, and Task 2.

**Known risk:** the `zle -N`-at-source-time vs non-interactive test interaction — handled explicitly in Task 1 Step 4 with the `zle -l` guard.
