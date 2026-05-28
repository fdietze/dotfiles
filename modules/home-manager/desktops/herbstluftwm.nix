{
  desktop,
  theme,
  lib,
  pkgs,
  config,
  hostLocal,
  uiFonts,
  ...
}: let
  stylixPalette = config.stylix.base16Scheme;
  withHash = value: "#${value}";
  currentThemeTarget = "theme-${theme}.target";
  herbstclient = "${pkgs.herbstluftwm}/bin/herbstclient";
  # PipeWire exposes a PulseAudio-compatible server on this system. Build
  # Polybar with Pulse support so the native internal/pulseaudio module works.
  polybar = pkgs.polybar.override {
    pulseSupport = true;
  };
  polybarRuntimePath = lib.makeBinPath [
    pkgs.bash
    # polybar-status deliberately calls stable CLI tools for slow Bluetooth and
    # Wi-Fi labels while keeping hot counters on direct /proc and /sys reads.
    pkgs.bluez
    pkgs.coreutils
    pkgs.networkmanager
    polybar
  ];
  bluetoothToggle = pkgs.writeShellApplication {
    name = "bluetooth-toggle";
    runtimeInputs = [
      pkgs.bluez
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      # Use bluetoothctl's interactive mode because direct one-shot "show"
      # does not reliably print controller data on this machine.
      controller="$(printf 'show\n' | bluetoothctl)"

      if grep -q 'Powered: yes' <<< "$controller"; then
        printf 'power off\n' | bluetoothctl
      else
        printf 'power on\n' | bluetoothctl
      fi
    '';
  };
  hlwmTitleFont = "${uiFonts.monospace.name}:size=${toString uiFonts.sizes.statusbar}";
  hlwmTitleHeight = toString (uiFonts.sizes.statusbar + 6);
  hlwmTitleDepth = toString (lib.max 4 (uiFonts.sizes.statusbar - 4));
  sessionColors = {
    background = withHash stylixPalette.base00;
    surface = withHash stylixPalette.base01;
    surfaceRaised = withHash stylixPalette.base02;
    foreground = withHash stylixPalette.base05;
    foregroundAlt = withHash stylixPalette.base03;
    warn = withHash stylixPalette.base08;
    urgent = withHash stylixPalette.base09;
    accent = withHash stylixPalette.base0B;
  };
  polybarColors = {
    background = sessionColors.background;
    foreground = sessionColors.foreground;
    foregroundAlt = sessionColors.foregroundAlt;
    warn = sessionColors.warn;
    peak = sessionColors.accent;
    tagDefaultBg = withHash stylixPalette.base00;
    tagEmptyFg =
      if theme == "light"
      then withHash stylixPalette.base02
      else withHash stylixPalette.base03;
    tagUsedFg = withHash stylixPalette.base05;
    tagSelectedFg = withHash stylixPalette.base00;
    tagUrgentBg = sessionColors.urgent;
    tagFocusBg = sessionColors.accent;
    tagFocusOtherBg = withHash stylixPalette.base02;
    tagUnfocusBg = withHash stylixPalette.base01;
    tagUnfocusOtherBg = withHash stylixPalette.base00;
  };
  hlwmColors = {
    barBg = sessionColors.background;
    barFg = sessionColors.foreground;
    borderNormal = sessionColors.surface;
    borderFocused = sessionColors.accent;
    urgent = sessionColors.urgent;
    tabBg = sessionColors.surface;
    tabMutedFg = sessionColors.foregroundAlt;
    tabOuter = sessionColors.surfaceRaised;
  };
  hlwmThemeCommands = ''
    ${herbstclient} attr theme.border_width 3
    ${herbstclient} set frame_border_width 1
    ${herbstclient} attr theme.floating.border_width 3

    ${herbstclient} set frame_border_active_color ${lib.escapeShellArg hlwmColors.borderFocused}
    ${herbstclient} set frame_border_normal_color ${lib.escapeShellArg hlwmColors.borderNormal}

    # Prefer theme attributes over the window_border_* compatibility aliases.
    # See herbstluftwm(1), "theme".
    ${herbstclient} attr theme.color ${lib.escapeShellArg hlwmColors.barBg}
    ${herbstclient} attr theme.title_color ${lib.escapeShellArg hlwmColors.barFg}
    ${herbstclient} attr theme.title_font ${lib.escapeShellArg hlwmTitleFont}
    ${herbstclient} attr theme.title_height ${hlwmTitleHeight}
    ${herbstclient} attr theme.title_depth ${hlwmTitleDepth}
    ${herbstclient} attr theme.title_when one_tab
    ${herbstclient} attr theme.active.color ${lib.escapeShellArg hlwmColors.borderFocused}
    ${herbstclient} attr theme.active.title_color ${lib.escapeShellArg hlwmColors.barBg}
    ${herbstclient} attr theme.active.title_font ${lib.escapeShellArg hlwmTitleFont}
    ${herbstclient} attr theme.active.title_height ${hlwmTitleHeight}
    ${herbstclient} attr theme.active.title_depth ${hlwmTitleDepth}
    ${herbstclient} attr theme.active.tab_title_color ${lib.escapeShellArg hlwmColors.tabMutedFg}
    ${herbstclient} attr theme.normal.color ${lib.escapeShellArg hlwmColors.barBg}
    ${herbstclient} attr theme.normal.title_color ${lib.escapeShellArg hlwmColors.barFg}
    ${herbstclient} attr theme.normal.title_font ${lib.escapeShellArg hlwmTitleFont}
    ${herbstclient} attr theme.normal.title_height ${hlwmTitleHeight}
    ${herbstclient} attr theme.normal.title_depth ${hlwmTitleDepth}
    ${herbstclient} attr theme.normal.tab_title_color ${lib.escapeShellArg hlwmColors.tabMutedFg}
    ${herbstclient} attr theme.urgent.color ${lib.escapeShellArg hlwmColors.urgent}
    ${herbstclient} attr theme.urgent.inner_color ${lib.escapeShellArg hlwmColors.urgent}
    ${herbstclient} attr theme.urgent.outer_color ${lib.escapeShellArg hlwmColors.urgent}
    ${herbstclient} attr theme.urgent.title_color ${lib.escapeShellArg hlwmColors.barBg}
    ${herbstclient} attr theme.urgent.title_font ${lib.escapeShellArg hlwmTitleFont}
    ${herbstclient} attr theme.urgent.title_height ${hlwmTitleHeight}
    ${herbstclient} attr theme.urgent.title_depth ${hlwmTitleDepth}
    ${herbstclient} attr theme.tab_color ${lib.escapeShellArg hlwmColors.tabBg}
    ${herbstclient} attr theme.tab_title_color ${lib.escapeShellArg hlwmColors.tabMutedFg}
    ${herbstclient} attr theme.tab_outer_color ${lib.escapeShellArg hlwmColors.tabOuter}

    # With smart_window_surroundings and tabbed_max, visible tabs use
    # theme.minimal; see https://github.com/herbstluftwm/herbstluftwm/issues/1518
    ${herbstclient} attr theme.minimal.color ${lib.escapeShellArg hlwmColors.barBg}
    ${herbstclient} attr theme.minimal.title_color ${lib.escapeShellArg hlwmColors.barFg}
    ${herbstclient} attr theme.minimal.title_font ${lib.escapeShellArg hlwmTitleFont}
    ${herbstclient} attr theme.minimal.title_height ${hlwmTitleHeight}
    ${herbstclient} attr theme.minimal.title_depth ${hlwmTitleDepth}
    ${herbstclient} attr theme.minimal.title_when multiple_tabs
    ${herbstclient} attr theme.minimal.active.color ${lib.escapeShellArg hlwmColors.borderFocused}
    ${herbstclient} attr theme.minimal.active.title_color ${lib.escapeShellArg hlwmColors.barBg}
    ${herbstclient} attr theme.minimal.active.title_font ${lib.escapeShellArg hlwmTitleFont}
    ${herbstclient} attr theme.minimal.active.title_height ${hlwmTitleHeight}
    ${herbstclient} attr theme.minimal.active.title_depth ${hlwmTitleDepth}
    ${herbstclient} attr theme.minimal.active.tab_title_color ${lib.escapeShellArg hlwmColors.tabMutedFg}
    ${herbstclient} attr theme.minimal.normal.color ${lib.escapeShellArg hlwmColors.barBg}
    ${herbstclient} attr theme.minimal.normal.title_color ${lib.escapeShellArg hlwmColors.barFg}
    ${herbstclient} attr theme.minimal.normal.title_font ${lib.escapeShellArg hlwmTitleFont}
    ${herbstclient} attr theme.minimal.normal.title_height ${hlwmTitleHeight}
    ${herbstclient} attr theme.minimal.normal.title_depth ${hlwmTitleDepth}
    ${herbstclient} attr theme.minimal.normal.tab_title_color ${lib.escapeShellArg hlwmColors.tabMutedFg}
    ${herbstclient} attr theme.minimal.urgent.color ${lib.escapeShellArg hlwmColors.urgent}
    ${herbstclient} attr theme.minimal.urgent.inner_color ${lib.escapeShellArg hlwmColors.urgent}
    ${herbstclient} attr theme.minimal.urgent.outer_color ${lib.escapeShellArg hlwmColors.urgent}
    ${herbstclient} attr theme.minimal.urgent.title_color ${lib.escapeShellArg hlwmColors.barBg}
    ${herbstclient} attr theme.minimal.urgent.title_font ${lib.escapeShellArg hlwmTitleFont}
    ${herbstclient} attr theme.minimal.urgent.title_height ${hlwmTitleHeight}
    ${herbstclient} attr theme.minimal.urgent.title_depth ${hlwmTitleDepth}
    ${herbstclient} attr theme.minimal.tab_color ${lib.escapeShellArg hlwmColors.tabBg}
    ${herbstclient} attr theme.minimal.tab_title_color ${lib.escapeShellArg hlwmColors.tabMutedFg}
    ${herbstclient} attr theme.minimal.tab_outer_color ${lib.escapeShellArg hlwmColors.tabOuter}
  '';
  polybarSettings = import ./polybar/settings.nix {
    inherit
      lib
      pkgs
      polybarColors
      uiFonts
      ;
    garminHeartRateAddress = hostLocal.devices.garminHeartRateAddress;
  };
  themeSwitchCommand = mode: "${config.home.profileDirectory}/bin/theme-${mode}";
  applyHlwmTheme = pkgs.writeShellScript "apply-hlwm-theme-${theme}" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ${herbstclient} version >/dev/null 2>&1 || exit 0

    ${herbstclient} attr theme.tiling.reset 1
    ${herbstclient} attr theme.floating.reset 1
    ${hlwmThemeCommands}
  '';
  runPolybar = pkgs.writeShellScript "run-polybar-${theme}" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    polybar_pids=()

    stop_polybars() {
      if [ "''${#polybar_pids[@]}" -gt 0 ]; then
        ${pkgs.coreutils}/bin/kill "''${polybar_pids[@]}" 2>/dev/null || true
        # Polybar can block on tailing custom modules during shutdown. Keep
        # theme switches bounded instead of waiting for systemd's stop timeout.
        for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
          alive=()
          for pid in "''${polybar_pids[@]}"; do
            if ${pkgs.coreutils}/bin/kill -0 "$pid" 2>/dev/null; then
              alive+=("$pid")
            fi
          done
          if [ "''${#alive[@]}" -eq 0 ]; then
            break
          fi
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        if [ "''${#alive[@]}" -gt 0 ]; then
          ${pkgs.coreutils}/bin/kill -KILL "''${alive[@]}" 2>/dev/null || true
        fi
        wait "''${polybar_pids[@]}" 2>/dev/null || true
      fi
    }

    trap 'stop_polybars; exit 0' INT TERM

    # Log to stdout/stderr so systemd-journald owns the lifecycle logs. This
    # avoids a stale /tmp log file and keeps `journalctl --user -u polybar-*`
    # as the single debugging entrypoint.
    echo "Polybar launch script started at $(${pkgs.coreutils}/bin/date)"

    HLWM_MONITOR_IDS=$(${pkgs.herbstluftwm}/bin/herbstclient list_monitors | ${pkgs.coreutils}/bin/cut -d':' -f1)
    echo "HLWM_MONITOR_IDS: $HLWM_MONITOR_IDS"

    POLYBAR_MONITOR_IDS_PRIMARY=$(${polybar}/bin/polybar --list-monitors | ${pkgs.gawk}/bin/awk -F: '{print $1 ($2~/primary/?" (primary)":"")}')
    echo "POLYBAR_MONITOR_IDS_PRIMARY: $POLYBAR_MONITOR_IDS_PRIMARY"

    MERGED=$(${pkgs.coreutils}/bin/paste -d " " <(${pkgs.coreutils}/bin/echo "$HLWM_MONITOR_IDS") <(${pkgs.coreutils}/bin/echo "$POLYBAR_MONITOR_IDS_PRIMARY"))
    echo "MERGED: $MERGED"

    PRIMARY=$(${pkgs.gnugrep}/bin/grep "primary" <<<"$MERGED" || true)
    OTHERS=$(${pkgs.gnugrep}/bin/grep -v "primary" <<<"$MERGED" || true)
    echo "PRIMARY: $PRIMARY"
    echo "OTHERS: $OTHERS"

    if [ -n "$PRIMARY" ]; then
      export MONITOR=$(${pkgs.coreutils}/bin/cut -d" " -f2 <<<"$PRIMARY")
      export MONITOR_HLWM=$(${pkgs.coreutils}/bin/cut -d" " -f1 <<<"$PRIMARY")
      echo "Starting primary polybar on '$PRIMARY' -> HLWM: $MONITOR_HLWM, Polybar: $MONITOR"
      # Only the primary bar contains the internal tray. Secondary bars inherit
      # the same styling but omit tray ownership.
      ${polybar}/bin/polybar default &
      polybar_pids+=("$!")
    else
      echo "No primary monitor found by script. Not starting Polybar on primary."
    fi

    ${pkgs.coreutils}/bin/sleep 2

    while IFS= read -r monitor; do
      if [ -z "$monitor" ]; then
        continue
      fi

      export MONITOR=$(${pkgs.coreutils}/bin/cut -d" " -f2 <<<"$monitor")
      export MONITOR_HLWM=$(${pkgs.coreutils}/bin/cut -d" " -f1 <<<"$monitor")
      echo "Starting secondary polybar on '$monitor' -> HLWM: $MONITOR_HLWM, Polybar: $MONITOR"
      ${polybar}/bin/polybar secondary &
      polybar_pids+=("$!")
    done <<<"$OTHERS"

    echo "Polybar launch script finished at $(${pkgs.coreutils}/bin/date)"

    if [ "''${#polybar_pids[@]}" -eq 0 ]; then
      echo "No Polybar instances were started."
      exit 1
    fi

    wait "''${polybar_pids[@]}"
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

    stylix.targets.dunst.enable = true;

    programs.autorandr = {
      enable = true;
      profiles = {
        default = {
          fingerprint = {
            eDP-1 = "00ffffffffffff0006af362000000000001b0104a51f117802fbd5a65334b6250e505400000001010101010101010101010101010101e65f00a0a0a040503020350035ae100000180000000f0000000000000000000000000020000000fe0041554f0a202020202020202020000000fe004231343051414e30322e30200a00d2";
          };
          config = {
            eDP-1 = {
              enable = true;
              crtc = 0;
              primary = true;
              position = "0x0";
              mode = "2560x1440";
              rate = "60.01";
            };
          };
        };
        portable-monitor-left = {
          fingerprint = {
            DP-2 = "00ffffffffffff004a8bb5a501010101141e0104b5351d783fee91a3544c99260f5054210800d1c001010101950001018180010181c040d000a0f0703e803020350061632100001a000000fc004d473134302d555430310a2020000000ff0064656d6f7365742d310a203020000000fd00283d88883c010a20202020202001d702032df2529001020304131f2021223c3d3e4c5d5e5f60e200c023097f0783010000e305c000e6060501525200023a801871382d40582c250061632100001e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000032";
            eDP-1 = "00ffffffffffff0006af362000000000001b0104a51f117802fbd5a65334b6250e505400000001010101010101010101010101010101e65f00a0a0a040503020350035ae100000180000000f0000000000000000000000000020000000fe0041554f0a202020202020202020000000fe004231343051414e30322e30200a00d2";
          };
          config = {
            DP-2 = {
              enable = true;
              crtc = 1;
              position = "0x0";
              mode = "3840x2160";
              rate = "59.98";
            };
            eDP-1 = {
              enable = true;
              crtc = 0;
              primary = true;
              position = "3840x360";
              mode = "2560x1440";
              rate = "60.01";
            };
          };
        };
      };
      hooks.postswitch = {
        run-theme = "${pkgs.systemd}/bin/systemctl --user start ${currentThemeTarget}";
      };
    };

    services.picom = {
      enable = false; # if tearing, re-enable
      backend = "glx";
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
        # GTK apps in the X11 herbstluftwm session read the icon theme through
        # XSettings. Keep this in sync with gtk.iconTheme for tray clients that
        # resolve status icons from the session instead of settings.ini.
        "Net/IconThemeName" = "Adwaita";
        "Net/ThemeName" = "adw-gtk3-${theme}";
      };
    };
    services.network-manager-applet.enable = true;
    services.flameshot = {
      enable = true;
      settings = {
        General = {
          contrastOpacity = 51;
          disabledTrayIcon = false;
          drawColor = "#9ECE6A";
          filenamePattern = "%F_%H-%M-%S";
          savePath = config.xdg.userDirs.extraConfig.XDG_SCREENSHOTS_DIR;
          savePathFixed = true;
          showStartupLaunchMessage = false;
        };
      };
    };
    services.redshift = {
      # Redshift adjusts the color temperature of your screen. This may help your eyes hurt less if you are working in front of the screen at night.
      enable = true;
      provider = "geoclue2";
    };
    services.unclutter = {
      # hide mouse after some seconds of no movement
      enable = true;
    };
    services.polybar = {
      enable = true;
      package = polybar;
      settings = polybarSettings;
      # The theme-specific service below launches the concrete Polybar config for
      # this specialization instead of Home Manager's default user service.
      script = ":";
    };
    xdg.configFile."polybar/config.ini".force = true;
    systemd.user.services.polybar.Install.WantedBy = lib.mkForce [];
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
        Description = "Polybar for ${theme} theme";
        After = [
          "graphical-session.target"
          "hlwm-${theme}.service"
        ];
        PartOf = [currentThemeTarget];
        # Home Manager's sd-switch activation restarts user services when
        # X-Restart-Triggers changes.
        X-Restart-Triggers = [
          config.xdg.configFile."polybar/config.ini".source
        ];
        X-SwitchMethod = "restart";
      };
      Service = {
        # systemd.kill(5) warns against KillMode=none because child processes
        # escape the service lifecycle. Keep Polybar in the cgroup instead.
        Type = "exec";
        Environment = "PATH=${polybarRuntimePath}:/run/wrappers/bin";
        ExecStart = "${runPolybar}";
        Restart = "on-failure";
        RestartSec = "2s";
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
          # Use PATH for repo-managed helper scripts so editing home/bin remains
          # immediate and bindings do not depend on the removed ~/bin directory.
          # terminal-here wraps $TERMINAL (kitty) with xcwd-home for cwd inheritance.
          # See modules/home-manager/launchers.nix.
          Mod4-d = "spawn terminal-here";
          Mod4-y = "spawn rofi -show run -modi run,calc,emoji";
          Mod4-b = "spawn ${lib.getExe pkgs.overskride}";
          Mod4-Ctrl-b = "spawn ${lib.getExe bluetoothToggle}";
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
          XF86MonBrightnessDown = "spawn ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
          XF86MonBrightnessUp = "spawn ${pkgs.brightnessctl}/bin/brightnessctl set +5%";
          XF86TouchpadToggle = "spawn touchpadtoggle";
          XF86AudioRaiseVolume = "spawn pamixer --increase 5";
          XF86AudioLowerVolume = "spawn pamixer --decrease 5";
          XF86AudioMute = "spawn pamixer -t";
          # bluetooth
          XF86Bluetooth = "spawn ${lib.getExe bluetoothToggle}";

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

          Mod4-Ctrl-Shift-s = "spawn $HOME/bin/frottage-save";
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

          # Keep startup styling in sync with the theme-switching service.
          ${hlwmThemeCommands}

          # frottage & # set wallpaper

          # xsetroot -cursor_name left_ptr # apply cursor theme globally

          (${pkgs.coreutils}/bin/sleep 1; ${pkgs.systemd}/bin/systemctl --user start ${currentThemeTarget}) &
          (${pkgs.coreutils}/bin/sleep 2; ${pkgs.systemd}/bin/systemctl --user start keepassxc.service) &
        '';
      };
    };
  }
