#!/bin/bash

hc() { "${herbstclient_command[@]:-herbstclient}" "$@" ;}
monitor=${1:-0}
geometry=( $(herbstclient monitor_rect "$monitor") )
if [ -z "$geometry" ] ;then
echo "Invalid monitor $monitor"
    exit 1
fi
# geometry has the format W H X Y
trayer_width=175
x=${geometry[0]}
y=${geometry[1]}
let panel_width=${geometry[2]}-$trayer_width
panel_height=22

font="-*-Droid Sans Mono-*-*-*-*-13-*-*-*-*-*-*-*"
charwidth=8.3
bgcolor='#121212'
fgcolor='#efefef'
bgcolorsel='#37BAFF'
fgcolorsel='#101010'

hc pad $monitor $panel_height
herbstclient emit_hook quit_panel

function uniq_linebuffered() {
   awk '$0 != l { print ; l=$0 ; fflush(); }' "$@"
}
 
{
   conky -c ~/.config/herbstluftwm/conkybar | while read -r; do
      echo -e "conky $REPLY";
     
  done > >(uniq_linebuffered)  &
   childpid=$!
   herbstclient --idle
   kill $childpid
} | {
   TAGS=( $(herbstclient tag_status $monitor) )
      conky=""
      separator="^fg($bgcolorsel)^ro(1x18)^fg()"
      while true; do
          for i in "${TAGS[@]}"; do
              echo -n "^ca(1,herbstclient use ${i:1})"
              case ${i:0:1} in
                  '#')
                      echo -n "^bg($bgcolorsel) ^fg($fgcolorsel)${i:1}^fg($fgcolor) ^bg($bgcolor)"
                      ;;
                  ':')
                      echo -n "^fg(#CCCCCC) ${i:1} "
                      ;;
                  *)
                      echo -n "^fg(#444444) ${i:1} "
                      ;;
              esac
              echo -n "^ca()"
          done
          echo -n " $separator "
          echo -n `herbstclient attr clients.focus.title`
          conky_text_only=$(echo -n "$conky" | sed 's.\^[^(]*([^)]*)..g')
          widthf=$(echo "(`echo "$conky_text_only" | wc -m`-1)*$charwidth" | bc -l)
          width=$( printf "%.0f" $widthf )
          echo -n "^p(_RIGHT)^p(-$width)$conky"
          echo
          read line || break
          cmd=( $line )
          case "$cmd[0]" in
              tag*)
                  TAGS=( $(herbstclient tag_status $monitor) )
                  ;;
              conky*)
                  conky=$(echo -n "$line"|sed 's/^conky //')
                  ;;
          esac
      done
} 2> /dev/null | dzen2 -w $panel_width -x $x -y $y -fn "$font" -h $panel_height \
              -e 'button3=' \
              -ta l -bg "$bgcolor" -fg $fgcolor &
pids+=($!)

# trayer tint color is the panel color +1 on each channel
trayer --edge top --widthtype pixel --width $trayer_width --heighttype pixel --height 22 --align right --tint 0x131313 --transparent true --alpha 0&
pids+=($!)

herbstclient --wait '^(quit_panel|reload).*'
kill -TERM "${pids[@]}" >/dev/null 2>&1
exit 0
