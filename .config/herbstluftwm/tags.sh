#!/usr/bin/env bash
hc() { "${herbstclient_command[@]:-herbstclient}" "$@" ;}
monitor=$1

THEME=$(cat $HOME/.theme || echo "light")


case $THEME in
    light)
        default_bg="#ffffff"
        empty_fg="#CCCCCC"
        used_fg="#555555"
        selected_fg="#ffffff"
        urgent_bg="#FFD8AC"
        focus_bg="#5A5B66"
        focus_other_bg="#BDBFD6"
        unfocus_bg="#A2A4B8"
        unfocus_other_bg=#DFE1FC
        # fgcolordim="#909090"
        # fgcolorbad="#FF3F74"
        ;;
    dark)
        default_bg="#191C26"
        empty_fg="#555555"
        used_fg="#EFEFEF"
        selected_fg="#ffffff"
        urgent_bg="#CE6D00"
        focus_bg="#5A5B66"
        focus_other_bg="#393940"
        unfocus_bg="#393940"
        unfocus_other_bg=#29292E
        # fgcolordim="#909090"
        # fgcolorbad="#FF3F74"
        ;;
esac

tag_status() {
    IFS=$'\t' read -ra tags <<< "$(hc tag_status $monitor)"


    for i in "${tags[@]}" ; do
        case ${i:0:1} in
            '#') # Focused monitor: the tag is viewed on this monitor
                echo -n "%{B$focus_bg F$selected_fg}"
                ;;
            '-') # Focused monitor: the tag is viewed on other monitor
                echo -n "%{B$focus_other_bg F#$used_fg}"
                ;;
            '+') # Unfocused monitor: the tag is viewed on this monitor
                echo -n "%{B$unfocus_bg F$selected_fg}"
                ;;
            '%') # Unfocused monitor: the tag is viewed on other monitor
                echo -n "%{B$unfocus_other_bg F$used_fg}"
                ;;
            '!') # the tag contains an urgent window
                echo -n "%{B$urgent_bg F$used_fg}"
                ;;
            ':') # the tag is used (not empty).
                echo -n "%{B$default_bg F$used_fg}"
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
