#!/bin/bash

# disable touch while typing
# syndaemon -t -k -i 2 & 

# set up keyboard layouts and toggle shortcut
setxkbmap -layout de,de -variant neo,basic -option -option grp:menu_toggle

# initialize keybindings
xbindkeys

# disable number keys to get used to the ones of NEO
# xmodmap -e 'keycode 10='
# xmodmap -e 'keycode 11='
# xmodmap -e 'keycode 12='
# xmodmap -e 'keycode 13='
# xmodmap -e 'keycode 14='
# xmodmap -e 'keycode 15='
# xmodmap -e 'keycode 16='
# xmodmap -e 'keycode 17='
# xmodmap -e 'keycode 18='
# xmodmap -e 'keycode 19='

# reset colorscheme
rm ~/.colors

# pasystray &
/usr/bin/start-pulseaudio-x11
# nm-applet &
# bluetooth-applet &
# dropboxd &

# hide mouse after some seconds
unclutter -idle 3 -jitter 5 -noevents -root &

exec dbus-launch herbstluftwm --locked

