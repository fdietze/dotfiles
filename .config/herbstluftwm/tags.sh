#!/usr/bin/env bash
hc() { "${herbstclient_command[@]:-herbstclient}" "$@" ;}
monitor=$1

THEME=$(cat $HOME/.theme || echo "light")


case $THEME in
    light)
        default_bg="#ffffff"
        used_fg="#555555"
        empty_fg="#CCCCCC"
        # fgcolordim="#909090"
        # fgcolorbad="#FF3F74"
        bgcolorsel="#5A5B66"
        fgcolorsel="#ffffff"
        bgcolorurgent="#FFD8AC"
        ;;
    dark)
        default_bg="#191C26"
        used_fg="#EFEFEF"
        empty_fg="#555555"
        # fgcolordim="#909090"
        # fgcolorbad="#FF3F74"
        bgcolorsel="#5A5B66"
        fgcolorsel="#ffffff"
        bgcolorurgent="#CE6D00"
        ;;
esac

tag_status() {
    IFS=$'\t' read -ra tags <<< "$(hc tag_status $monitor)"


    for i in "${tags[@]}" ; do
        case ${i:0:1} in
            ':') # the tag is used (not empty).
                echo -n "%{B$default_bg F$used_fg}"
                ;;
            '+') # the tag is viewed on the specified MONITOR, but this monitor is not focused.
                echo -n "%{B#A2A4B8 F$fgcolorsel}"
                ;;
            '#') # the tag is viewed on the specified MONITOR and it is focused.
                echo -n "%{B$bgcolorsel F$fgcolorsel}"
                ;;
            '-') # the tag is viewed on a different MONITOR, but this monitor is not focused.
                echo -n "%{B#BDBFD6 F#$used_fg}"
                ;;
            '%') # the tag is viewed on a different MONITOR and it is focused.
                echo -n "%{B#DFE1FC F$used_fg}"
                ;;
            '!') # the tag contains an urgent window
                echo -n "%{B$bgcolorurgent F$used_fg}"
                ;;
            *)
                echo -n "%{B$default_bg F$empty_fg}"
                ;;
        esac
        echo -n " ${i:1} "
    done
    # echo "%{O0}" # for showing last space
    echo -n "%{B$default_bg F$default_fg}" # reset colors
}

{
    echo "tag_changed" # to trigger initial update
    hc --idle
} | {
while read action rest; do
case $action in tag*)
    echo $(tag_status)
    ;; esac
done
}
