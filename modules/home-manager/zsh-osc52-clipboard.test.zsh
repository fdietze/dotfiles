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
got=$(print -rn -- hello | OSC52_OUT=/dev/stdout TMUX= STY= osc52-copy)
[[ "$got" == "$expected" ]] || fail "stdin input: got ${(q)got}"

# tmux passthrough wraps in ESC P tmux; ... ESC backslash with ESC doubled
tmux_expected=$'\ePtmux;\e\e]52;c;aGVsbG8=\a\e\\'
got=$(TMUX=/tmp/x,0,0 STY= OSC52_OUT=/dev/stdout osc52-copy hello)
[[ "$got" == "$tmux_expected" ]] || fail "tmux wrap: got ${(q)got}"

print "PASS"
