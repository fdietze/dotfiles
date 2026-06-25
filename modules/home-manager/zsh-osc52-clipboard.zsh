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
  local esc=$'\e'
  local seq="$esc]52;c;$b64"$'\a'
  # tmux/screen need the escape wrapped in DCS passthrough, ESC doubled, so the
  # multiplexer forwards it to the outer terminal instead of swallowing it.
  # ($'..' isn't expanded inside double quotes, so use $esc for the ESC byte.)
  if [[ -n "$TMUX" ]]; then
    seq="${esc}Ptmux;${seq//$esc/$esc$esc}$esc\\"
  elif [[ -n "$STY" ]]; then
    seq="${esc}P${seq//$esc/$esc$esc}$esc\\"
  fi
  printf '%s' "$seq" > "${OSC52_OUT:-/dev/tty}"
}

# Clipboard read -> stdout. Queries the terminal and parses its OSC 52 reply.
# Reply format: ESC ] 52 ; c ; <base64> <terminator>, where the terminator is
# BEL (\a) OR ST (ESC backslash) depending on the terminal. Earlier versions
# waited only for BEL with `read -t 1 -d`, but zsh's -t guards only the initial
# availability check, not the whole read: once any byte arrives, read blocks
# forever on the missing delimiter, and stty raw has disabled isig so ctrl-c is
# a mere byte -> hard freeze. So: non-blocking tty (min 0 time 0), read one
# byte at a time under a bounded iteration deadline, accept BOTH terminators,
# and restore stty in `always {}` so a stuck read can never strand the tty.
osc52-paste() {
  local old reply='' c i=0
  old=$(stty -g </dev/tty) || return
  {
    stty raw -echo min 0 time 0 </dev/tty
    printf '\e]52;c;?\e\\' > /dev/tty
    # ~2 s worst case (200 * 10 ms) when the terminal answers nothing; returns
    # as soon as a terminator arrives when it does.
    while (( i++ < 200 )); do
      IFS= read -r -k 1 -t 0.01 c </dev/tty && reply+=$c
      [[ $reply == *$'\a' || $reply == *$'\e\\' ]] && break
    done
  } always {
    stty "$old" </dev/tty
  }
  # Strip everything up to the last "52;c;", then any trailing terminator.
  reply=${reply##*52;c;}
  reply=${reply%$'\a'}; reply=${reply%$'\e\\'}; reply=${reply%$'\e'}
  [[ -n "$reply" ]] && printf '%s' "$reply" | base64 -d 2>/dev/null
}

# ZLE: override the builtin vi widget names so existing keybindings pick these
# up automatically (no manual bindkey). Copy widgets sync $CUTBUFFER out after
# running; paste widgets pull the system clipboard into CUTBUFFER first.
# `zle -l` succeeds only when ZLE is available (interactive shell); skip in the
# non-interactive unit test where `zle -N` would error.
if zle -l >/dev/null 2>&1; then
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
