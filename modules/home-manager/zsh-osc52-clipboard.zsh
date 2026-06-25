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
