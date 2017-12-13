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
# setxkbmap -model apple -layout de,de -variant neo,basic -option -option grp:menu_toggle, altwin:swap_alt_win, lv5:rwin_switch_lock
# apple keyboard <> fix: options hid_apple iso_layout=0 >> /etc/modprobe.d/hid_apple.conf

xss-lock -- i3lock --color=DDDDDD --nofork --ignore-empty-password &

# load screen color profile
if [ -f ~/.config/screen-color-profile.icm ]; then
    xcalib ~/.config/screen-color-profile.icm &
fi

# keyring
# eval $(/usr/bin/gnome-keyring-daemon --start --components=pkcs11,secrets,ssh)
# export SSH_AUTH_SOCK

# now we can launch the window manager
exec herbstluftwm --locked

