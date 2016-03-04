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
setxkbmap -layout de,de -variant neo,basic -option -option grp:menu_toggle &

xss-lock -- i3lock --color=333333 --nofork --ignore-empty-password &

# load screen color profile
xcalib ~/projects/dotfiles/Asus_UX21A_FHD_matt_CMN__N116HSE_EA1.icm &

# keyring
# eval $(/usr/bin/gnome-keyring-daemon --start --components=pkcs11,secrets,ssh)
# export SSH_AUTH_SOCK

# now we can launch the window manager
exec herbstluftwm --locked

