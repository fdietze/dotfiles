#!/bin/bash

on=$(synclient -l | grep -c 'TouchpadOff.*=.*0')
if [ "$on" == "1" ]; then
    synclient TouchpadOff=1
    xdotool mousemove 1920 1080
else
    synclient TouchpadOff=0
    xdotool mousemove 940 480
fi
