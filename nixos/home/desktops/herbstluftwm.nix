{
  desktop ? "gnome",
  theme,
  lib,
  pkgs,
  config,
  uiFonts,
  ...
}: let
  stylixPalette = config.stylix.base16Scheme;
  withHash = value: "#${value}";
  currentThemeTarget = "theme-${theme}.target";
  polybarRuntimePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.docker
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.herbstluftwm
    pkgs.iotop
    pkgs.iputils
    pkgs.linuxPackages.cpupower
    pkgs.polybar
    pkgs.procps
    pkgs.timewarrior
    pkgs.xdotool
  ];
  hlwmColors = {
    barBg = withHash stylixPalette.base00;
    barFg = withHash stylixPalette.base05;
    barFgAlt =
      if theme == "light"
      then "#888888"
      else withHash stylixPalette.base03;
    barWarn =
      if theme == "light"
      then "#FF3F74"
      else "#FF5370";
    barPeak = withHash stylixPalette.base0B;
    borderNormal =
      if theme == "light"
      then "#E8E9F2"
      else "#171717";
    borderFocused = withHash stylixPalette.base0B;
  };
  themeSwitchCommand = mode: "${config.home.profileDirectory}/bin/theme-${mode}";
  applyHlwmTheme = pkgs.writeShellScript "apply-hlwm-theme-${theme}" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    hc=${pkgs.herbstluftwm}/bin/herbstclient
    $hc version >/dev/null 2>&1 || exit 0

    $hc attr theme.tiling.reset 1
    $hc attr theme.floating.reset 1
    $hc set window_border_width 3
    $hc set frame_border_width 1
    $hc attr theme.floating.border_width 3

    $hc set frame_border_active_color ${lib.escapeShellArg hlwmColors.borderFocused}
    $hc set frame_border_normal_color ${lib.escapeShellArg hlwmColors.borderNormal}
    $hc set window_border_active_color ${lib.escapeShellArg hlwmColors.borderFocused}
    $hc set window_border_normal_color ${lib.escapeShellArg hlwmColors.borderNormal}

    $hc attr theme.color ${lib.escapeShellArg hlwmColors.barBg}
    $hc attr theme.title_color ${lib.escapeShellArg hlwmColors.barFg}
    $hc attr theme.active.color ${lib.escapeShellArg hlwmColors.borderFocused}
    $hc attr theme.active.title_color ${lib.escapeShellArg hlwmColors.barBg}
    $hc attr theme.urgent.color orange
    $hc attr theme.urgent.title_color ${lib.escapeShellArg hlwmColors.barBg}
  '';
  restartPolybar = pkgs.writeShellScript "restart-polybar-${theme}" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    export BAR_BG=${lib.escapeShellArg hlwmColors.barBg}
    export BAR_FG=${lib.escapeShellArg hlwmColors.barFg}
    export BAR_FG_ALT=${lib.escapeShellArg hlwmColors.barFgAlt}
    export BAR_WARN=${lib.escapeShellArg hlwmColors.barWarn}
    export BAR_PEAK=${lib.escapeShellArg hlwmColors.barPeak}
    export BAR_RAMP_0="%{F$BAR_FG_ALT}▁%{F-}"
    export BAR_RAMP_7="%{F$BAR_PEAK}█%{F-}"
    export BAR_RAMP_WARN_0="%{F$BAR_WARN}▁%{F-}"
    export BAR_RAMP_WARN_1="%{F$BAR_WARN}▂%{F-}"
    export BAR_HEIGHT=24

    ${pkgs.procps}/bin/pkill -x polybar || true
    ${pkgs.coreutils}/bin/sleep 1

    echo "Polybar launch script started at $(${pkgs.coreutils}/bin/date)" > /tmp/polybar_launch.log

    HLWM_MONITOR_IDS=$(${pkgs.herbstluftwm}/bin/herbstclient list_monitors | ${pkgs.coreutils}/bin/cut -d':' -f1)
    echo "HLWM_MONITOR_IDS: $HLWM_MONITOR_IDS" >> /tmp/polybar_launch.log

    POLYBAR_MONITOR_IDS_PRIMARY=$(${pkgs.polybar}/bin/polybar --list-monitors | ${pkgs.gawk}/bin/awk -F: '{print $1 ($2~/primary/?" (primary)":"")}')
    echo "POLYBAR_MONITOR_IDS_PRIMARY: $POLYBAR_MONITOR_IDS_PRIMARY" >> /tmp/polybar_launch.log

    MERGED=$(${pkgs.coreutils}/bin/paste -d " " <(${pkgs.coreutils}/bin/echo "$HLWM_MONITOR_IDS") <(${pkgs.coreutils}/bin/echo "$POLYBAR_MONITOR_IDS_PRIMARY"))
    echo "MERGED: $MERGED" >> /tmp/polybar_launch.log

    PRIMARY=$(${pkgs.gnugrep}/bin/grep "primary" <<<"$MERGED" || true)
    OTHERS=$(${pkgs.gnugrep}/bin/grep -v "primary" <<<"$MERGED" || true)
    echo "PRIMARY: $PRIMARY" >> /tmp/polybar_launch.log
    echo "OTHERS: $OTHERS" >> /tmp/polybar_launch.log

    if [ -n "$PRIMARY" ]; then
      export MONITOR=$(${pkgs.coreutils}/bin/cut -d" " -f2 <<<"$PRIMARY")
      export MONITOR_HLWM=$(${pkgs.coreutils}/bin/cut -d" " -f1 <<<"$PRIMARY")
      echo "Starting polybar on primary monitor '$PRIMARY' -> HLWM: $MONITOR_HLWM, Polybar: $MONITOR" >> /tmp/polybar_launch.log
      ${pkgs.polybar}/bin/polybar >> /tmp/polybar_launch.log 2>&1 &
    else
      echo "No primary monitor found by script. Not starting Polybar on primary." >> /tmp/polybar_launch.log
    fi

    ${pkgs.coreutils}/bin/sleep 2

    while IFS= read -r monitor; do
      if [ -z "$monitor" ]; then
        continue
      fi

      export MONITOR=$(${pkgs.coreutils}/bin/cut -d" " -f2 <<<"$monitor")
      export MONITOR_HLWM=$(${pkgs.coreutils}/bin/cut -d" " -f1 <<<"$monitor")
      echo "Starting polybar on other monitor '$monitor' -> HLWM: $MONITOR_HLWM, Polybar: $MONITOR" >> /tmp/polybar_launch.log
      ${pkgs.polybar}/bin/polybar >> /tmp/polybar_launch.log 2>&1 &
    done <<<"$OTHERS"

    echo "Polybar launch script finished at $(${pkgs.coreutils}/bin/date)" >> /tmp/polybar_launch.log
  '';
in
lib.mkIf (desktop == "herbstluftwm") {
  home.shellAliases = {
    hc = "${pkgs.herbstluftwm}/bin/herbstclient";
  };
  home.sessionVariables = {
    # Keep winit-based X11 apps like Alacritty from auto-scaling to the panel's
    # physical DPI, so they match the Wayland session more closely.
    WINIT_X11_SCALE_FACTOR = "1";
  };

  services.picom = {
    enable = true;
    vSync = true;
  };
  gtk = {
    # Home Manager's GTK module writes both the per-user settings.ini files and
    # the matching org.gnome.desktop.interface dconf keys.
    gtk3.colorScheme = theme;
    gtk4.colorScheme = theme;
  };
  services.xsettingsd = {
    enable = true;
    settings = {
      "Net/ThemeName" = "adw-gtk3-${theme}";
    };
  };
  services.network-manager-applet.enable = true;
  systemd.user.services."hlwm-${theme}" = {
    Unit = {
      Description = "Apply HerbstluftWM ${theme} theme";
      After = ["graphical-session.target"];
      PartOf = [currentThemeTarget];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${applyHlwmTheme}";
    };
    Install.WantedBy = [currentThemeTarget];
  };
  systemd.user.services."polybar-${theme}" = {
    Unit = {
      Description = "Restart Polybar for ${theme} theme";
      After = [
        "graphical-session.target"
        "hlwm-${theme}.service"
      ];
      PartOf = [currentThemeTarget];
    };
    Service = {
      Type = "oneshot";
      KillMode = "none";
      # Temporary workaround until the polybar config is migrated into Nix and
      # can reference store paths directly instead of relying on a shell PATH.
      Environment = "PATH=${polybarRuntimePath}:${config.home.homeDirectory}/bin:${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin";
      ExecStart = "${restartPolybar}";
    };
    Install.WantedBy = [currentThemeTarget];
  };

  # systemd.user.services.xsettingsd = {
  #   Unit = {
  #     Description = "xsettingsd";
  #     After = ["graphical-session-pre.target"];
  #     PartOf = ["graphical-session.target"];
  #   };
  #
  #   Install.WantedBy = ["graphical-session.target"];
  #
  #   Service = {
  #     Environment = "PATH=${config.home.profileDirectory}/bin";
  #     ExecStart =
  #       "${pkgs.xsettingsd}/bin/xsettingsd"
  #       + optionalString (cfg.configFile != null)
  #       " -c ${escapeShellArg cfg.configFile}";
  #     Restart = "on-abort";
  #   };
  # };

  services.dunst = {
    # https://github.com/dunst-project/dunst/blob/master/dunstrc
    # old configFile = "$HOME/.config/dunst/dunstrc.old";
    enable = true;
    # settings = {
    #   global = {
    #     frame_width = 1;
    #     frame_color = "#9ECE6A";
    #     font = "Monospace 7";
    #   };
    #   urgency_normal = {
    #     background = "#191C26";
    #     foreground = "#eceff1";
    #   };
    # };
  };

  programs.rofi = {
    # application launcher, window switcher, ssh launcher
    enable = true;

    theme = let
      fetchedContent = builtins.fetchurl {
        url = "https://raw.githubusercontent.com/newmanls/rofi-themes-collection/c2be059e9507785d42fc2077a4c3bc2533760939/themes/squared-everforest.rasi";
        sha256 = "14p055gbqr7wijahjmd8jr04jn6nscs2zx3fyiy42c4n8yi0v98f";
      };
      fileContent = builtins.readFile fetchedContent;
      # replace font in theme with monospace font.
      replacedContent =
        builtins.replaceStrings
        [
          ''"FiraCode Nerd Font Medium 12"''
          "width:      480;"
        ]
        [''"${uiFonts.monospace.name} ${toString uiFonts.sizes.popups}"'' "width: 1000;"]
        fileContent;
    in
      builtins.toFile "squared-everforest-modified.rasi" replacedContent;

    plugins = with pkgs; [
      rofi-calc
      rofi-emoji
      # rofi-bluetooth
      # rofi-vpn
      # rofi-systemd
      # rofi-pulse-select
      # rofi-file-browser
    ];
    extraConfig = {
      modi = "run,calc,emoji";
      run-list-command = ''bash -ic "alias | awk -F'[ =]' '{print \$2}'"'';
      run-command = "bash -ic '{cmd}'";
    };
  };

  # disabled, because it reloads at boot time
  # home.activation.reloadHerbstluftwm =
  #   config.lib.dag.entryBetween [ "reloadSystemD" ] [ "onFilesChange" ] ''
  #     echo reloading herbstluftwm
  #     ${pkgs.herbstluftwm}/bin/herbstclient reload
  #   '';

  xsession = {
    enable = true;
    windowManager.herbstluftwm = {
      enable = true; # generates ~/.config/herbstluftwm/autostart
      tags = [
        "1"
        "2"
        "3"
        "4"
        "5"
        "6"
        "7"
        "8"
        "9"
      ];
      keybinds = {
        Mod4-d = "spawn sh -c 'alacritty --working-directory \"$($HOME/bin/xcwd-home)\"'";
        # Mod4-d =
        #   "spawn sh -c '${pkgs.ghostty}/bin/ghostty --working-directory=\"$($HOME/bin/xcwd-home)\"'";
        # Mod4-d = "spawn sh -c 'wezterm start --cwd \"$($HOME/bin/xcwd-home)\"'";
        Mod4-y = "spawn rofi -show run -modi run,calc,emoji";
        Mod4-b = "spawn rofi-bluetooth";
        Mod4-j = "spawn $BROWSER";
        # Mod4-´ = "spawn $BROWSER";
        Mod4-apostrophe = "spawn $BROWSER";

        Mod4-q = "close";
        Mod4-x = "close";
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
        Mod4-Shift-c = "chain , move_index +1 --skip-visible , use_index +1 --skip-visible";
        Mod4-Shift-Ctrl-c = "move_index +1 --skip-visible";
        Mod4-v = "use_index -1 --skip-visible";
        Mod4-Shift-v = "chain , move_index -1 --skip-visible , use_index -1 --skip-visible";
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
        Mod4-F7 = "spawn autorandr --change"; # detect connected monitors, apply right profile

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
        Mod4-Ctrl-k = "spawn ${themeSwitchCommand "light"}";
        Mod4-Ctrl-s = "spawn ${themeSwitchCommand "dark"}";

        # media keys
        # XF86KbdBrightnessDown = "spawn keyboardbacklightoff"; # TODO
        # XF86KbdBrightnessUp = "spawn keyboardbacklightmax"; # TODO
        XF86MonBrightnessDown = "spawn ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
        XF86MonBrightnessUp = "spawn ${pkgs.brightnessctl}/bin/brightnessctl set +5%";
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
        Mod4-Ctrl-g = "spawn ${pkgs.brightnessctl}/bin/brightnessctl set +5%";
        Mod4-Ctrl-r = "spawn ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
        Mod4-Ctrl-Shift-g = "spawn ${pkgs.brightnessctl}/bin/brightnessctl set +1%";
        Mod4-Ctrl-Shift-r = "spawn ${pkgs.brightnessctl}/bin/brightnessctl set 1%-";

        #   # control media players with yxcvb (üöäpz on NEO)
        Mod4-udiaeresis = "spawn playerctl previous";
        Mod4-odiaeresis = "spawn playerctl play";
        Mod4-adiaeresis = "spawn playerctl play-pause";
        Mod4-p = "spawn playerctl stop";
        Mod4-z = "spawn playerctl next";

        Mod4-Shift-odiaeresis = "spawn ${pkgs.timewarrior}/bin/timew continue";
        Mod4-Shift-p = "spawn ${pkgs.timewarrior}/bin/timew stop";

        # Screenshots
        Print = "spawn ${pkgs.scrot}/bin/scrot 'screenshots/%Y-%m-%d_%H-%M-%S.png' --exec '${pkgs.libnotify}/bin/notify-send --expire-time=2000 \"Fullscreen Screenshot Saved.\"'";
        Ctrl-Mod4-Print = "spawn ${pkgs.flameshot}/bin/flameshot gui -r | ${pkgs.xclip}/bin/xclip -selection clipboard -t image/png"; # https://github.com/flameshot-org/flameshot/issues/635#issuecomment-2302675095

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
        smart_window_surroundings = true; # must be false to show tabs
        smart_frame_surroundings = true;
        focus_stealing_prevention = true; # zoom problems
        # TODO different frame and window border color

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
        "class='mpv' floating=on"
        # "class='feh' floating=on floatplacement=center"
        ''class="Signal" tag=1''
        ''class="VirtualBox Manager" tag=6''
        ''class="KeePassXC" windowtype='_NET_WM_WINDOW_TYPE_NORMAL' tag=8''
        ''class="KeePassXC" windowtype='_NET_WM_WINDOW_TYPE_DIALOG' focus=on switchtag=on floatplacement=center'' # keepass dialogs
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
        # alias hc="${pkgs.herbstluftwm}/bin/herbstclient"

        # tags keybindings
        tag_names=({1..9})
        tag_keys=({1..9} 0)

        herbstclient rename default "''${tag_names[0]}" || true
        for i in ''${!tag_names[@]}; do
        	herbstclient add "''${tag_names[$i]}"
        	key="''${tag_keys[$i]}"
        	if ! [ -z "$key" ]; then
        		herbstclient keybind "Mod4-$key" use_index "$i"
        		herbstclient keybind "Mod4-Shift-$key" chain , move_index "$i" , use_index "$i"
        		herbstclient keybind "Mod4-Shift-Ctrl-$key" move_index "$i"
        	fi
        done

        # tabs
        herbstclient attr theme.title_font 'Monospace:pixelsize=16'  # example using Xft
        herbstclient attr theme.title_height 15 # Pixel height for title text
        herbstclient attr theme.title_depth 5  # Pixels below title text
        herbstclient attr theme.title_when one_tab # tabbed mode in 'max' layout
        herbstclient attr theme.minimal.title_height 25
        herbstclient attr theme.minimal.title_when multiple_tabs
        # herbstclient attr theme.minimal.color $BAR_BG
        # herbstclient attr theme.minimal.title_color $BAR_FG
        # herbstclient attr theme.minimal.title_depth 8
        # herbstclient attr theme.minimal.title_font "Monospace:pixelsize=20"

        # frottage & # set wallpaper

        # xsetroot -cursor_name left_ptr # apply cursor theme globally

        (${pkgs.coreutils}/bin/sleep 1; ${pkgs.systemd}/bin/systemctl --user start ${currentThemeTarget}) &
        (${pkgs.coreutils}/bin/sleep 2; ${pkgs.systemd}/bin/systemctl --user start keepassxc.service) &



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
      # https://github.com/NixOS/nixpkgs/issues/119513
      if [ -z "$_XPROFILE_SOURCED" ]; then
        export _XPROFILE_SOURCED=1

        (
          function current_wifi {
            ${pkgs.networkmanager}/bin/nmcli -t -f active,ssid dev wifi | grep -E '^yes' | cut -d: -f2
          }

          # autorandr --change & # detect monitors
          (
            set -e
            sleep 120
            # if current wifi is not empty and not "kronk" (mobile hotspot), start megasync
            CURRENT_WIFI=$(current_wifi)
            echo $CURRENT_WIFI > /tmp/current_wifi
            if [ -n "$CURRENT_WIFI" ] && [ "$CURRENT_WIFI" != "kronk" ]; then
              ${pkgs.megasync}/bin/megasync > /tmp/megasync_logs 2>&1 &
            fi
          ) &
        ) >/tmp/xsession_debug 2>&1 &
      fi
    '';
  };
}
