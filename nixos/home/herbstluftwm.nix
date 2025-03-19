{ pkgs, config, ... }: {

  home.shellAliases = { hc = "${pkgs.herbstluftwm}/bin/herbstclient"; };

  home.activation.reloadHerbstluftwm =
    config.lib.dag.entryBetween [ "reloadSystemD" ] [ "onFilesChange" ] ''
      echo reloading herbstluftwm
      ${pkgs.herbstluftwm}/bin/herbstclient reload
    '';

  xsession = {
    enable = true;
    windowManager.herbstluftwm = {
      enable = true; # generates ~/.config/herbstluftwm/autostart
      tags = [ "1" "2" "3" "4" "5" "6" "7" "8" "9" ];
      keybinds = {
        # launchers
        # if there is an alacritty window, spawn a new window.
        # Working directory is current directory of currently focused window.
        # Mod4-d = "spawn sh -c 'alacritty msg create-window --working-directory \"$($HOME/bin/xcwd-home)\" || alacritty --working-directory \"$($HOME/bin/xcwd-home)\"'";
        Mod4-d =
          "spawn sh -c 'alacritty --working-directory \"$($HOME/bin/xcwd-home)\"'";
        # Mod4-d = "spawn sh -c 'wezterm start --cwd \"$($HOME/bin/xcwd-home)\"'";
        Mod4-Shift-d =
          "chain , rule once class=Alacritty floating=on floatplacement=center , spawn alacritty -e sh -c 'source $HOME/bin/secret-envs && aichat'";
        Mod4-y = "spawn rofi -show run -modi run,calc,emoji";
        Mod4-b = "spawn rofi-bluetooth";
        Mod4-j = "spawn $BROWSER";
        # Mod4-´ = "spawn $BROWSER";
        Mod4-Apostrophe = "spawn $BROWSER";

        Mod4-q = "close_and_remove";
        Mod4-x = "close_and_remove";
        Mod4-k = "spawn xkill";

        # focusing clients (iale are positions of neo layout arrow keys)
        Mod4-Left = "focus left";
        Mod4-Down = "focus down";
        Mod4-Up = "focus up";
        Mod4-Right = "focus right";
        Mod4-i = "focus left";
        Mod4-a = "focus down";
        Mod4-l = "focus up";
        Mod4-e = "focus right";
        Mod4-Tab = "cycle +1";
        Mod4-Shift-Tab = "cycle -1";
        # TODO: cycle all, to reach floating windows, --skip-invisible

        # moving clients
        Mod4-Shift-Left = "shift left";
        Mod4-Shift-Down = "shift down";
        Mod4-Shift-Up = "shift up";
        Mod4-Shift-Right = "shift right";
        Mod4-Shift-i = "shift left";
        Mod4-Shift-a = "shift down";
        Mod4-Shift-l = "shift up";
        Mod4-Shift-e = "shift right";

        # cycle through tags
        Mod4-c = "use_index +1 --skip-visible";
        Mod4-Shift-c =
          "chain , move_index +1 --skip-visible , use_index +1 --skip-visible";
        Mod4-Shift-Ctrl-c = "move_index +1 --skip-visible";
        Mod4-v = "use_index -1 --skip-visible";
        Mod4-Shift-v =
          "chain , move_index -1 --skip-visible , use_index -1 --skip-visible";
        Mod4-Shift-Ctrl-v = "move_index -1 --skip-visible";
        Mod4-w = "use_previous";
        Mod4-Shift-w = "spawn $HOME/bin/hc-move-previous";

        # splitting frames
        # create an empty frame at the specified direction ( .62 is golden ratio)
        Mod4-g = "chain , split top 0.38 , focus up";
        Mod4-r = "chain , split bottom 0.62 , focus down";
        Mod4-n = "chain , split left 0.38 , focus left";
        Mod4-t = "chain , split right 0.62 , focus right";

        # resizing frames
        Mod4-Shift-g = "resize up +0.02";
        Mod4-Shift-r = "resize down +0.02";
        Mod4-Shift-n = "resize left +0.02";
        Mod4-Shift-t = "resize right +0.02";

        # layouting
        # let the current frame explode into subframes
        Mod4-m = "split explode";
        Mod4-Shift-m = "split explode";
        # collapse the current frame
        Mod4-comma = "remove";
        Mod4-Shift-comma = "remove";
        Mod4-Shift-h = "cycle_layout 1 vertical max horizontal";
        # Mod4-Shift-h = "cycle_layout 1 grid vertical horizontal";
        Mod4-f = "fullscreen toggle";
        Mod4-h = "set_attr clients.focus.floating toggle";

        # focus monitors
        Mod4-o = "focus_monitor +1";
        Mod4-u = "focus_monitor -1";
        Mod4-Shift-o = "chain , shift_to_monitor +1 , focus_monitor +1";
        Mod4-Shift-u = "chain , shift_to_monitor -1 , focus_monitor -1";
        Mod4-Shift-Ctrl-o = "shift_to_monitor +1";
        Mod4-Shift-Ctrl-u = "shift_to_monitor -1";
        Mod4-F7 =
          "spawn autorandr --change"; # detect connected monitors, apply right profile

        # window manager & system
        Mod4-Shift-q = "quit";
        Mod4-Shift-x = "quit";
        Mod4-Shift-y = "reload";
        Mod4-Ctrl-Shift-q = "spawn poweroff";
        Mod4-Ctrl-Shift-x = "spawn poweroff";
        Mod4-Ctrl-Shift-y = "spawn reboot";
        # lock screen
        Mod4-Escape = "spawn bash -c 'loginctl lock-session'";

        #   # switch color scheme
        Mod4-Ctrl-k = "spawn bash -c '$HOME/bin/theme light > /dev/null 2>&1'";
        Mod4-Ctrl-s = "spawn bash -c '$HOME/bin/theme dark > /dev/null 2>&1'";

        # media keys
        XF86KbdBrightnessDown = "spawn keyboardbacklightoff";
        XF86KbdBrightnessUp = "spawn keyboardbacklightmax";
        XF86MonBrightnessDown = "spawn light -U 5";
        XF86MonBrightnessUp = "spawn light -A 5";
        XF86TouchpadToggle = "spawn touchpadtoggle";
        XF86AudioRaiseVolume = "spawn pamixer --increase 5";
        XF86AudioLowerVolume = "spawn pamixer --decrease 5";
        XF86AudioMute = "spawn pamixer -t";
        # bluetooth
        XF86Bluetooth = "spawn bluetoothtoggle";

        # adjust volume
        Mod4-Ctrl-h = "spawn pamixer --increase 5";
        Mod4-Ctrl-n = "spawn pamixer --decrease 5";
        Mod4-Ctrl-m = "spawn pamixer -t";

        # adjust screen brightness
        Mod4-Ctrl-g = "spawn light -A 5";
        Mod4-Ctrl-r = "spawn light -U 5";
        Mod4-Ctrl-Shift-g = "spawn light -A 1";
        Mod4-Ctrl-Shift-r = "spawn light -U 1";

        #   # control media players with yxcvb (üöäpz on NEO)
        Mod4-udiaeresis = "spawn playerctl previous";
        Mod4-odiaeresis = "spawn playerctl play";
        Mod4-adiaeresis = "spawn playerctl play-pause";
        Mod4-p = "spawn playerctl stop";
        Mod4-z = "spawn playerctl next";

        # Screenshots
        Print =
          "spawn ${pkgs.scrot}/bin/scrot 'screenshots/%Y-%m-%d_%H-%M-%S.png' --exec '${pkgs.libnotify}/bin/notify-send --expire-time=2000 \"Fullscreen Screenshot Saved.\"'";
        Ctrl-Mod4-Print =
          "spawn ${pkgs.flameshot}/bin/flameshot gui -r | ${pkgs.xclip}/bin/xclip -selection clipboard -t image/png"; # https://github.com/flameshot-org/flameshot/issues/635#issuecomment-2302675095

        # incubator
        # Mod4- = "keepmenu ~/";

        # wallpapers
        #   hc keybind ''$Mod-Ctrl-Shift-n spawn ''$HOME/bin/frottage
        Mod4-Ctrl-Shift-s = "spawn $HOME/bin/frottage-save";
        #   hc keybind ''$Mod-Ctrl-Shift-s spawn ''$HOME/bin/frottage-save
        #   # hc keybind ''$Mod-Ctrl-Shift-Right spawn ''$HOME/projects/wpfr/seek 0.5
        #   # hc keybind ''$Mod-Ctrl-Shift-Left spawn ''$HOME/projects/wpfr/seek -0.5
        #   # hc keybind ''$Mod-Ctrl-Shift-m spawn ''$HOME/projects/wpfr/play
        #   # hc keybind ''$Mod-Ctrl-Shift-comma spawn ''$HOME/projects/wpfr/stop
      };

      mousebinds = {
        # mouse
        Mod4-B1 = "move"; # click + drag
        Mod4-B3 = "resize"; # right click + drag
        Mod1-B1 = "resize"; # easier resize for touchpads
        Mod4-B2 = "zoom"; # middle click: resize in all directions
      };

      settings = {
        default_frame_layout = "grid";

        auto_detect_monitors = true;
        mouse_recenter_gap = 1;

        focus_crosses_monitor_boundaries = true;

        always_show_frame = 1;
        window_border_inner_width = 0;
        frame_bg_transparent = 1;
        frame_transparent_width = 0;
        frame_border_inner_width = 0;
        frame_gap = 0;
        window_gap = 0;
        frame_padding = 0;
        smart_window_surroundings = false; # must be false to show tabs
        smart_frame_surroundings = true;
        focus_stealing_prevention = true; # zoom problems

        tabbed_max = true; # show tabs in max layout
      };

      rules = [
        "focus=on" # normally focus new clients
        "floatplacement=smart" # tries to place it with as little overlap to other floating windows as possible
        "fixedsize floating=on" # matches if the window does not allow being resized
        "windowtype~'_NET_WM_WINDOW_TYPE_(DIALOG|UTILITY|SPLASH)' floating=on"
        "windowtype='_NET_WM_WINDOW_TYPE_DIALOG' focus=on"
        "windowtype~'_NET_WM_WINDOW_TYPE_(NOTIFICATION|DOCK|DESKTOP)' manage=off"

        # custom app rules
        "class='MEGAsync' floating=on"
        ''class="Signal" tag=1''
        ''class="VirtualBox Manager" tag=6''
        ''class="KeePassXC" windowtype='_NET_WM_WINDOW_TYPE_NORMAL' tag=8''
        ''
          class="KeePassXC" windowtype='_NET_WM_WINDOW_TYPE_DIALOG' focus=on switchtag=on floatplacement=center'' # keepass dialogs
        ''class="Spotify" tag=9''

        # zoom
        "class='zoom' title='zoom' floating=on tag=9" # notifications, sometimes detects the app window
        "class='zoom' title='Zoom Cloud Meetings' floating=on" # launch and closing screen
        "title~'^Zoom - .*' floating=off" # zoom app
        "class='zoom' title='Zoom' floating=off" # connecting to meeting...
        "title='Zoom Meeting' floating=off" # zoom meeting
        "class='zoom' title='share_preview_window' floating=on hook=close-hook" # screen sharing preview popup
      ];

      extraConfig = ''
        # tags keybindings
        tag_names=({1..9})
        tag_keys=({1..9} 0)

        hc rename default "''${tag_names[0]}" || true
        for i in ''${!tag_names[@]}; do
        	hc add "''${tag_names[$i]}"
        	key="''${tag_keys[$i]}"
        	if ! [ -z "$key" ]; then
        		herbstclient keybind "Mod4-$key" use_index "$i"
        		herbstclient keybind "Mod4-Shift-$key" chain , move_index "$i" , use_index "$i"
        		herbstclient keybind "Mod4-Shift-Ctrl-$key" move_index "$i"
        	fi
        done

        source "$HOME/bin/theme-env" # gives different colors depending on "$HOME/.theme"
        herbstclient attr theme.tiling.reset 1
        herbstclient attr theme.floating.reset 1
        herbstclient set window_border_width 3
        herbstclient set frame_border_width 1
        herbstclient attr theme.floating.border_width 3

        herbstclient set frame_border_active_color $WM_BORDER_FOCUSED
        herbstclient set frame_border_normal_color $WM_BORDER_NORMAL
        herbstclient set window_border_active_color $WM_BORDER_FOCUSED
        herbstclient set window_border_normal_color $WM_BORDER_NORMAL

        # tabs
        herbstclient attr theme.title_font 'Monospace:pixelsize=16'  # example using Xft
        herbstclient attr theme.title_height 15 # Pixel height for title text
        herbstclient attr theme.title_depth 5  # Pixels below title text
        herbstclient attr theme.title_when one_tab # tabbed mode in 'max' layout
        herbstclient attr theme.color $BAR_BG
        herbstclient attr theme.title_color $BAR_FG # Foreground text color
        herbstclient attr theme.active.color $WM_BORDER_FOCUSED
        herbstclient attr theme.active.title_color $BAR_BG # Foreground text color
        herbstclient attr theme.urgent.color orange
        herbstclient attr theme.urgent.title_color $BAR_BG # Foreground text color





        frottage & # set wallpaper

        xsetroot -cursor_name left_ptr # apply cursor theme globally


        (
        pkill polybar || true
        pkill -9 polybar || true

        rm -f /tmp/msgg
        set -e

        # show polybar tray on primary monitor
        # https://github.com/polybar/polybar/issues/1070


        HLWM_MONITOR_IDS=$(${pkgs.herbstluftwm}/bin/herbstclient list_monitors | cut -d':' -f1)
        # example line: 0
        echo "command $(${pkgs.herbstluftwm}/bin/herbstclient list_monitors)" >> /tmp/msgg
        echo HLWM_MONITOR_IDS: $HLWM_MONITOR_IDS >> /tmp/msgg

        POLYBAR_MONITOR_IDS_PRIMARY=$(polybar --list-monitors | awk -F: '{print $1 ($2~/primary/?" (primary)":"")}')
        # example line: eDP-1 (primary)
        echo POLYBAR_MONITOR_IDS_PRIMARY: $POLYBAR_MONITOR_IDS_PRIMARY >> /tmp/msgg

        MERGED=$(paste -d " " <(echo "$HLWM_MONITOR_IDS") <(echo "$POLYBAR_MONITOR_IDS_PRIMARY"))
        # example line: 0 eDP-1 (primary)
        echo MERGED: $MERGED >> /tmp/msgg

        PRIMARY=$(echo "$MERGED" | grep "primary" || true)
        OTHERS=$(echo "$MERGED" | grep -v "primary" || true)
        echo PRIMARY: $PRIMARY >> /tmp/msgg
        echo OTHERS: $OTHERS >> /tmp/msgg


        # first, launch polybar on primary monitor
        export MONITOR=$(echo "$PRIMARY" | cut -d" " -f2) # used in ~/.config/polybar/config.ini
        export MONITOR_HLWM=$(echo "$PRIMARY" | cut -d" " -f1) # passed via ~/.config/polybar/config.ini to ~/.config/herbstluftwm/tags.sh
        echo "Starting polybar on primary monitor '$PRIMARY' $MONITOR_HLWM ($MONITOR)" >> /tmp/msgg
        ${pkgs.polybar}/bin/polybar &

        # after waiting a bit, launch polybar on other monitors
        sleep 2
        IFS=$'\n' # loop over whole lines
        echo "$OTHERS" | while read -r m; do
            # if line is empty, skip
            if [ -z "$m" ]; then
                continue
            fi
            export MONITOR=$(echo "$m" | cut -d" " -f2)
            export MONITOR_HLWM=$(echo "$m" | cut -d" " -f1)
            # Start polybar in the background and optionally manage PIDs
            echo "Starting polybar on other monitor '$m' $MONITOR_HLWM ($MONITOR)" >> /tmp/msgg
            ${pkgs.polybar}/bin/polybar &
        done
        ) > /tmp/polybar.log 2>&1



      '';

      # extraConfig = ''
      #
      #   # hc keybind ''$Mod-d spawn sh -c 'alacritty msg create-window --working-directory "''$(''$HOME/bin/xcwd-home)" -e bash -c "source ~/.zshenv; exec zsh" || alacritty --working-directory "''$(''$HOME/bin/xcwd-home)" -e bash -c "source ~/.zshenv; exec zsh"' # alias from .sh_aliases
      #   # hc keybind ''$Mod-d spawn sh -c 'wezterm start --cwd "''$(''$HOME/bin/xcwd-home)" -- bash -c "source ~/.zshenv; exec zsh"'
      #   # hc keybind ''$Mod-d spawn sh -c 'rio --working-dir "''$(''$HOME/bin/xcwd-home)" --command bash -c "source ~/.zshenv; exec zsh"'
      #   # hc keybind ''$Mod-d spawn sh -c 'termite --directory "''$(''$HOME/bin/xcwd-home)" --exec "bash -c \"source ~/.zshenv; exec zsh\""'
      #   hc keybind ''$Mod-d spawn sh -c 'alacritty --working-directory "''$(''$HOME/bin/xcwd-home)"'
      #
      #   hc keybind ''$Mod-0 spawn sh -c 'xprop >> ~/propslog'
      #
      #
      #
      #
      #
      #
      #
      #
      #
      #
      #
      # win-info() (
      # 	win_id=''$1
      #
      # 	echo -n "''$win_id "
      #
      # 	match_int='[0-9][0-9]*'
      # 	match_string='".*"'
      # 	match_qstring='"[^"\\]*(\\.[^"\\]*)*"' # NOTE: Adds 1 backreference
      #
      # 	{
      # 		# Run xprop, transform its output into i3 criteria. Handle fallback to
      # 		# WM_NAME when _NET_WM_NAME isn't set
      # 		xprop -id ''$win_id |
      # 			sed -nr \
      # 				-e "s/^WM_CLASS\(STRING\) = (''$match_qstring), (''$match_qstring)''$/instance=\1\nclass=\3/p" \
      # 				-e "s/^WM_WINDOW_ROLE\(STRING\) = (''$match_qstring)''$/window_role=\1/p" \
      # 				-e "/^WM_NAME\(STRING\) = (''$match_string)''$/{s//title=\1/; h}" \
      # 				-e "/^_NET_WM_NAME\(UTF8_STRING\) = (''$match_qstring)''$/{s//title=\1/; h}" \
      # 				-e ' ''${g; p}' # remove space before double single quotes, was added for nix escaping to work
      # 	} | sort | tr "\n" " " | sed -r 's/^(.*) ''$/[\1]\n/'
      # )
      #
      #
      # herbstclient -il rule info-hook | while read win_id; do
      # 	win-info ''$win_id >>/tmp/hc-hooks
      # done &
      #
      #
      #
      #
      #   # rules
      #
      #   # close hook
      #   # https://github.com/herbstluftwm/herbstluftwm/issues/1536#issuecomment-1331169428
      #   herbstclient -il rule close-hook | while read win_id; do
      #   	herbstclient close ''$win_id
      #   	echo "close-hook: ''$win_id" >>/tmp/hc-hooks
      #   done &
      #
      #
      #   # rules
      #   #hc rule class=XTerm tag=3 # move all xterms to tag 3
      #   hc rule focus=on # normally focus new clients
      #   hc rule floatplacement=smart
      #   #hc rule focus=off # normally do not focus new clients
      #   # give focus to most common terminals
      #   hc rule class~'(.*[Rr]xvt.*|.*[Tt]erm|Konsole|alacritty)' focus=on
      #
      #
      #
      #
      #
      #   # for_window [title="alacritty-fzf-run"] floating enable, resize set 800 px 800 px; move position center; exec --no-startup-id xdotool search --title alacritty-fzf-run behave %@ blur windowclose
      #   hc rule title='alacritty-fzf-run' floating=on floatplacement=center
      #   hc rule class='mpv' floating=on floatplacement=center floating_geometry=1280x1024
      #   hc rule class='vlc' floating=on floatplacement=center floating_geometry=1280x1024
      #
      #   # intellij file finder dialog xprop:
      #   # WM_CLASS(STRING) = "sun-awt-X11-XWindowPeer", "jetbrains-studio"
      #   # WM_CLIENT_LEADER(WINDOW): window id # 0x3200023
      #   # _NET_WM_NAME(UTF8_STRING) = "win25"
      #   # WM_NAME(STRING) = "win25"
      #
      #   # unlock, just to be sure
      #   hc unlock
      #
      #   herbstclient set tree_style '╾│ ├└╼─┐'
      #
      #
      #   # "''$HOME/bin/theme" >/tmp/theme_debug 2>&1 &
      #   # "''$HOME/bin/theme" >/dev/null 2>&1 &
      #
      #   # wait
      # '';
    };
    profileExtra = ''
      (

      function current_wifi {
      	${pkgs.networkmanager}/bin/nmcli -t -f active,ssid dev wifi | grep -E '^yes' | cut -d: -f2
      }

      # https://github.com/NixOS/nixpkgs/issues/119513
      if [ -z "$_XPROFILE_SOURCED" ]; then
        export _XPROFILE_SOURCED=1

        autorandr --change & # detect monitors
        (sleep 2 && keepassxc) &
        (
          set -e
          sleep 60
          # if current wifi is not empty and not "kronk" (mobile hotspot), start megasync
          CURRENT_WIFI=$(current_wifi)
          echo $CURRENT_WIFI > /tmp/current_wifi
          if [ -n "$CURRENT_WIFI" ] && [ "$CURRENT_WIFI" != "kronk" ]; then
            # QT_SCALE_FACTOR fixes megasync UI
            # QT_SCALE_FACTOR=1
            ${pkgs.megasync}/bin/megasync > /tmp/megasync_logs 2>&1 &
          fi
        ) &
      fi
      wait
      ) >/tmp/xsession_debug 2>&1 &
    '';
  };
}
