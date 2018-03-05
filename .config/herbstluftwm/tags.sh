#!/usr/bin/env bash
hc() { "${herbstclient_command[@]:-herbstclient}" "$@" ;}
monitor=0


bgcolor="#121212"
fgcolor="#EFEFEF"
fgcolorinact="#444444"
fgcolordim="#909090"
fgcolorbad="#FF3F74"
bgcolorsel="#37BAFF"
fgcolorsel="#000000"
bgcolorurgent="#CE6D00"

tag_status() {
    IFS=$'\t' read -ra tags <<< "$(hc tag_status $monitor)"

    for i in "${tags[@]}" ; do
        case ${i:0:1} in
            '#')
                echo -n "%{B$bgcolorsel F$fgcolorsel}"
                ;;
            # '+')
            #     echo -n "%{B#9CA668 F#141414}"
            #     ;;
            ':')
                echo -n "%{B$bgcolor F$fgcolor}"
                ;;
            '!')
                echo -n "%{B$bgcolorurgent F$fgcolorsel}"
                ;;
            *)
                echo -n "%{B$bgcolor F$fgcolorinact}"
                ;;
        esac
        echo -n " ${i:1} "
    done
    echo "%{O0}" # for showing last space
    echo -n "%{B$bgcolor F$fgcolor}" # reset colors
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
