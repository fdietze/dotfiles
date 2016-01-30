#!/bin/bash

# needed as replacement for dbus-launch
if [ -d /etc/X11/xinit/xinitrc.d ] ; then
    for f in /etc/X11/xinit/xinitrc.d/?* ; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi

rm -f ~/.colors

xrdb load ~/.Xresources

# set up keyboard layouts and toggle shortcut
setxkbmap -layout de,de -variant neo,basic -option -option grp:menu_toggle

# now we can launch the window manager
exec herbstluftwm --locked

