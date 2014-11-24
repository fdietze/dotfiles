#!/bin/bash
trayer_width=60
if grep -q "dark" ~/.colors
then # dark
    font="-*-Droid Sans Mono-*-*-*-*-13-*-*-*-*-*-*-*"
    panel_height=21
    bgcolor=121212
else # light
    font="-*-Droid Sans Mono-*-*-*-*-15-*-*-*-*-*-*-*"
    panel_height=21
    bgcolor=FFFFFF
fi

conkyrc=~/.config/herbstluftwm/panel.conkyrc


hc() { "${herbstclient_command[@]:-herbstclient}" "$@" ;}
monitor=${1:-0}
geometry=( $(herbstclient monitor_rect "$monitor") )
if [ -z "$geometry" ] ;then
echo "Invalid monitor $monitor"
    exit 1
fi
# geometry has the format X Y W H
let panel_width=${geometry[2]}-$trayer_width
x=${geometry[0]}
y=${geometry[1]}


onetime_conky() { conky -c $conkyrc -i 2 -u 0 | tail -1 ;}
continous_conky() { conky -c $conkyrc ;}
hcevent_conky() { herbstclient --idle | while read; do onetime_conky; done ;}
uniq_linebuffered() { awk '$0 != l { print ; l=$0 ; fflush(); }' ;}
strip_dzen() { sed 's.\^[^(]*([^)]*)..g' ;}
width() { textwidth "$font" "$(echo "$@" | strip_dzen )" ;}
split_align() {
    # split conky line at IFS character
    # and produce dzen code to align first part left and second part right
    while read -r line; do
        IFS='&' read -ra PART <<< "$line"
        printf '%s\n' "$(jobs -pr)${PART[0]}^p(_RIGHT)^p(-$(width "${PART[1]} "))${PART[1]}"
    done
}
dzen_bar() {
    dzen2 -ta l -fn "$font" -bg "#$bgcolor" \
        -x $x -y $y -w $panel_width -h $panel_height
}

hc pad $monitor $panel_height
herbstclient emit_hook quit_panel



# render once on start, in conky intervals and on every herbstclient event
# TODO: capture pid of hcevent_conky and add to pids to kill later instead of killall herbstclient
cat <(hcevent_conky & continous_conky & onetime_conky) | uniq_linebuffered | split_align | dzen_bar &
pids+=($!)

trayer --edge top --widthtype pixel --width $trayer_width --heighttype pixel --height $panel_height --align right --tint 0x$bgcolor --transparent true --alpha 0 &
pids+=($!)




# kill background processes on termination signals
trap '[ -n "$(jobs -pr)" ] && kill $(jobs -pr)' INT QUIT TERM EXIT

# block until reload or quit event is triggered
herbstclient --wait '^(quit_panel|reload).*'
killall herbstclient
# and kill captured and background processes
kill -TERM "${pids[@]}" >/dev/null 2>&1
# kill -TERM $(jobs -pr) >/dev/null 2>&1
exit 0
