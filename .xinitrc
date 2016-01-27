#!/bin/bash

# needed as replacement for dbus-launch
if [ -d /etc/X11/xinit/xinitrc.d ] ; then
    for f in /etc/X11/xinit/xinitrc.d/?* ; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi

xrdb ~/.Xresources

# set up keyboard layouts and toggle shortcut
setxkbmap -layout de,de -variant neo,basic -option -option grp:menu_toggle &

# switch keyboard backlight off
keyboardbacklightoff

# initialize keybindings
xbindkeys &

# reset colorscheme
rm ~/.colors

# hide mouse after some seconds of no movement
unclutter --timeout 3 --fork # unclutter-xfixes

# load screen color profile
xcalib ~/projects/dotfiles/Asus_UX21A_FHD_matt_CMN__N116HSE_EA1.icm

# change color temperature depending on sun position
# not enabled, because it needs a running X session
systemctl --user start redshift &

# now we can launch the window manager
exec herbstluftwm --locked

