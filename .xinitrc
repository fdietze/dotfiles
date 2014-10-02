#!/bin/bash

# disable touch while typing
# syndaemon -t -k -i 2 & 

# initialize keybindings
xbindkeys

# disable number keys to get used to the ones of NEO
xmodmap -e 'keycode 10='
xmodmap -e 'keycode 11='
xmodmap -e 'keycode 12='
xmodmap -e 'keycode 13='
xmodmap -e 'keycode 14='
xmodmap -e 'keycode 15='
xmodmap -e 'keycode 16='
xmodmap -e 'keycode 17='
xmodmap -e 'keycode 18='
xmodmap -e 'keycode 19='


pasystray &
nm-applet &
bluetooth-applet &
dropboxd &


export DE="mate"

exec dbus-launch herbstluftwm --locked

