# OSC 52 clipboard for zsh (replaces zsh-system-clipboard)

## Problem

`zsh-system-clipboard` (shared via `modules/home-manager/shell.nix` →
`shell-core.nix`) searches for a clipboard binary (`wl-copy`/`xclip`/`xsel`/
`pbcopy`/`tmux`) at startup. On headless/remote hosts (e.g. `cubie`, a Debian
SBC reached over ssh) none exist, so it errors loudly on every shell init and
yank/paste never reaches the local clipboard.

Root cause: clipboard sync was tied to a *local* clipboard manager. Over ssh
there is no such thing.

## Decision

Replace `zsh-system-clipboard` entirely with a small OSC 52 mechanism. OSC 52
is a terminal escape (`ESC ]52;c;<base64> BEL`) that the *local* terminal
intercepts and applies to the *local* clipboard — it travels through the ssh
tty stream, needs no remote clipboard manager, no `$DISPLAY`, no X-forward.
One universal path for every host (local desktop + remote), and it removes a
plugin dependency.

Terminals are already configured to allow both directions:
- kitty: `clipboard_control = "write-clipboard write-primary read-clipboard read-primary no-append"` (`shared.nix`)
- ghostty: `terminal.osc52 = "CopyPaste"` (`shared.nix`)

Read (paste) is the security-gated half of OSC 52; it is open in our terminals
so `p` can pull the system clipboard into the line buffer.

## Mechanism — one repo-local file

New file `modules/home-manager/zsh-osc52-clipboard.zsh`, inlined into
`programs.zsh.initContent` via `builtins.readFile ./zsh-osc52-clipboard.zsh`
(real `.zsh` file = syntax highlighting + filename matches contents; no extra
store symlink).

### `osc52-copy` (the single authoritative clipboard write — DRY)

- Input: `"$*"` if args given, else read stdin (so it works as a pipe target).
- `base64 | tr -d '\n'` (coreutils `base64`, present in every host's nix closure).
- Multiplexer passthrough: if `$TMUX` set, wrap the escape in tmux DCS
  passthrough (`ESC Ptmux; … ESC \`, ESC-doubled); if `$STY` set, screen DCS
  wrapping. Else emit plain. This lets the *write* escape tmux/screen.
- `printf '\e]52;c;%s\a' "$b64" > /dev/tty`.

Used by both the ZLE copy widgets and the global `C` alias.

### `osc52-paste` (clipboard read → stdout)

- Save `stty`, set raw `-echo`, send query `\e]52;c;?\a` to `/dev/tty`.
- Read the response from `/dev/tty` with a short `read -t` timeout, parse the
  `52;c;<base64>` payload (terminated by BEL or `ESC \`), `base64 -d` to stdout.
- Always restore `stty` on exit (trap).

### ZLE integration (essentials only, vicmd + visual)

Override the **same** builtin widget names so every existing key binding picks
them up automatically (no manual `bindkey` rewrapping needed):

Copy widgets — run builtin, then push `$CUTBUFFER` through `osc52-copy`:
`vi-yank`, `vi-yank-whole-line`, `vi-delete`, `vi-delete-char`,
`vi-backward-delete-char`, `vi-change`.

Paste widgets — set `CUTBUFFER=$(osc52-paste)`, then run builtin:
`vi-put-after`, `vi-put-before`.

```zsh
for w in vi-yank vi-yank-whole-line vi-delete vi-delete-char \
         vi-backward-delete-char vi-change; do
  eval "_osc52_$w() { zle .$w; osc52-copy \"\$CUTBUFFER\" }"
  zle -N $w _osc52_$w
done
for w in vi-put-after vi-put-before; do
  eval "_osc52_$w() { CUTBUFFER=\$(osc52-paste); zle .$w }"
  zle -N $w _osc52_$w
done
```

## Wiring changes in `modules/home-manager/shell.nix`

1. Remove the `zsh-system-clipboard` entry from the `plugins` list.
2. Append `${builtins.readFile ./zsh-osc52-clipboard.zsh}` into `initContent`.
3. Change global alias `C = "| xclip -selection clipboard"` →
   `C = "| osc52-copy"` (unifies clipboard writes, drops the `xclip` dep here).

Lands on all hosts via shared `shell.nix`.

## Known caveats (documented in the file header)

- **Copy** escapes tmux/screen via DCS passthrough. **Read (`p`)** does not
  reliably traverse tmux/screen (they don't proxy OSC 52 read-back). Bare ssh
  works; inside tmux paste-from-system may fail — verify empirically, add a
  `tmux show-buffer` fallback later only if actually needed (YAGNI).
- Requires the terminal to allow silent `read-clipboard` (kitty/ghostty ✓;
  other terminals are copy-only or prompt).
- No chunking for huge payloads (single `printf`); CLI-sized yanks are fine.

## Out of scope

- Other clipboard touchpoints (nvf.nix OSC 52 already; noctalia/herbstluftwm
  desktop clipboards). Not part of this change.

## Verification

- `home-manager build --flake .#cubie` (and a desktop host) succeeds.
- On cubie over ssh in kitty: no startup error; `yy` then local Ctrl-Shift-V
  pastes the line; `echo hi | C` puts `hi` on the local clipboard; `p` in a
  shell inserts the local clipboard contents.
