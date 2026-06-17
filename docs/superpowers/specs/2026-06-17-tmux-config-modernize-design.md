# tmux config modernize — design

Date: 2026-06-17
File: `home/files/.tmux.conf` (→ `~/.tmux.conf` via home-manager dev symlink)
tmux: 3.6a

## Problem
Config is ~2019-era. `tmux source-file` emits 7 warnings (deprecated
`*-fg`/`*-bg`/`*-attr` options removed in tmux 2.9). Terminal type
`screen-256color` has no truecolor. Status clock spawns a `date|awk`
subprocess every second, fighting CPU deep-sleep.

## Decisions
- **Plugin-free.** Built-ins cover all needs. No tpm (KISS/YAGNI, no sandbox fetch).
- **Clipboard = OSC52** (`set -g set-clipboard on`) + vi copy keys. Terminal owns
  the clipboard; works on X11 (herbstluftwm) and Wayland (niri) and over SSH with
  zero external tools.
- **Status: native + lazy.** left=hostname, right=`#S | %d %b %Y  %H:%M`,
  `status-interval 5`. No subprocess, no per-second wake.
- **Colors = ANSI named only.** No hex/256 indices. Adapts to any terminal palette
  / theme (noctalia switches) automatically.
- **Drop** the `Home`/`End` `send Escape "OH"` hack — obsolete with `tmux-256color`.

## Changes
Terminal:
- `default-terminal "tmux-256color"`
- `set -as terminal-features ",*:RGB"`

Keep: prefix `C-a`, `escape-time 0`, `base-index 1`, pane-base 1, mouse on,
history 10000, vim pane/window/resize binds, `|`/`-` splits, `T` swap,
`C-a` last-window, 24h clock, titles.

Add: `mode-keys vi`, `set-clipboard on`, `renumber-windows on`, `focus-events on`,
copy-mode `v`=begin-selection / `y`=copy-selection.

Colors (all ANSI names): `status-style`, `window-status-current-style`,
`pane-active-border-style`, `message-style`, `clock-mode-colour`,
`display-panes-*-colour`.

## Verification
`tmux -f /dev/null new-session -d; tmux source-file <conf>` → exit 0, no warnings.
