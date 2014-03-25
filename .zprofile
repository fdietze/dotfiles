[[ -e ~/.profile  ]] && emulate sh -c 'source ~/.profile'
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx
