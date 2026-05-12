{
  lib,
  pkgs,
  polybarColors,
  uiFonts,
  garminHeartRateAddress,
  ...
}:
let
  awk = lib.getExe pkgs.gawk;
  coreutils = "${pkgs.coreutils}/bin";
  cpupower = "${pkgs.linuxPackages.cpupower}/bin/cpupower";
  docker = lib.getExe pkgs.docker;
  grep = lib.getExe pkgs.gnugrep;
  herbstclient = "${pkgs.herbstluftwm}/bin/herbstclient";
  pavucontrol = lib.getExe pkgs.pavucontrol;
  ping = "${pkgs.iputils}/bin/ping";
  sed = lib.getExe pkgs.gnused;
  sudo = "/run/wrappers/bin/sudo";
  timew = lib.getExe pkgs.timewarrior;
  xdotool = lib.getExe pkgs.xdotool;
  statusbarFontSize = toString uiFonts.sizes.statusbar;
  statusbarClockFontSize = toString (uiFonts.sizes.statusbar + 5);
  statusbarHeight = toString (uiFonts.sizes.statusbar * 2 + 4);
  statusbarFont =
    style: offset:
    "${uiFonts.monospace.name}:style=${style}:size=${statusbarFontSize};${toString offset}";
  statusbarClockFont =
    style: offset:
    "${uiFonts.monospace.name}:style=${style}:size=${statusbarClockFontSize};${toString offset}";

  hlwmTags = pkgs.writeShellApplication {
    name = "polybar-hlwm-tags";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.herbstluftwm
    ];
    text = ''
      hc() { herbstclient "$@"; }
      monitor="''${1:-0}"

      default_bg=${lib.escapeShellArg polybarColors.tagDefaultBg}
      default_fg=${lib.escapeShellArg polybarColors.foreground}
      empty_fg=${lib.escapeShellArg polybarColors.tagEmptyFg}
      used_fg=${lib.escapeShellArg polybarColors.tagUsedFg}
      selected_fg=${lib.escapeShellArg polybarColors.tagSelectedFg}
      urgent_bg=${lib.escapeShellArg polybarColors.tagUrgentBg}
      focus_bg=${lib.escapeShellArg polybarColors.tagFocusBg}
      focus_other_bg=${lib.escapeShellArg polybarColors.tagFocusOtherBg}
      unfocus_bg=${lib.escapeShellArg polybarColors.tagUnfocusBg}
      unfocus_other_bg=${lib.escapeShellArg polybarColors.tagUnfocusOtherBg}

      tag_status() {
        IFS=$'\t' read -ra tags <<< "$(hc tag_status "$monitor")"

        for i in "''${tags[@]}"; do
          case ''${i:0:1} in
            '#')
              echo -n "%{B$focus_bg F$selected_fg}"
              ;;
            '-')
              echo -n "%{B$focus_other_bg F$used_fg}"
              ;;
            '+')
              echo -n "%{B$unfocus_bg F$used_fg}"
              ;;
            '%')
              echo -n "%{B$unfocus_other_bg F$used_fg}"
              ;;
            '!')
              echo -n "%{B$urgent_bg F$used_fg}"
              ;;
            ':')
              echo -n "%{B$default_bg F$used_fg}"
              ;;
            *)
              echo -n "%{B$default_bg F$empty_fg}"
              ;;
          esac
          echo -n " ''${i:1} "
        done
        echo "%{B$default_bg F$default_fg}"
      }

      {
        echo "tag_changed"
        hc --idle
      } | while read -r action rest; do
        case "$action" in
          tag*)
            tag_status
            ;;
        esac
      done
    '';
  };

  topProcess = pkgs.writeShellApplication {
    name = "polybar-topprocess";
    runtimeInputs = [
      pkgs.gawk
      pkgs.gnugrep
      pkgs.procps
    ];
    text = ''
      top -d 5 -b \
        | grep "PID USER" -A 1 --line-buffered \
        | grep -v "\-\-\|PID USER" --line-buffered \
        | awk '{print ($9>10) ? $12 : ""; system("")}'
    '';
  };

  topIoRead = pkgs.writeShellApplication {
    name = "polybar-topioread";
    runtimeInputs = [
      pkgs.gawk
      pkgs.gnugrep
      pkgs.iotop
    ];
    text = ''
      iotop -d 10 -ob \
        | grep -v grep \
        | grep --line-buffered 'Total DISK' \
        | awk '{print $5,$6; system("")}'
    '';
  };

  topIoWrite = pkgs.writeShellApplication {
    name = "polybar-topiowrite";
    runtimeInputs = [
      pkgs.gawk
      pkgs.gnugrep
      pkgs.iotop
    ];
    text = ''
      iotop -d 10 -ob \
        | grep -v grep \
        | grep --line-buffered 'Total DISK' \
        | awk '{print $12,$13; system("")}'
    '';
  };

  ioRead = pkgs.writeShellApplication {
    name = "polybar-ioread";
    runtimeInputs = [ pkgs.gnused ];
    text = ''
      ${sudo} ${lib.getExe topIoRead} \
        | sed --unbuffered 's/^\(.*[MG]\/s.*\)$/%{F${polybarColors.peak}}\1%{F-}/' \
        | sed --unbuffered 's/^\(.*[^MG]\/s.*\)$/%{F${polybarColors.foreground}}\1%{F-}/'
    '';
  };

  ioWrite = pkgs.writeShellApplication {
    name = "polybar-iowrite";
    runtimeInputs = [ pkgs.gnused ];
    text = ''
      ${sudo} ${lib.getExe topIoWrite} \
        | sed --unbuffered 's/^\(.*[MG]\/s.*\)$/%{F${polybarColors.peak}}\1%{F-}/' \
        | sed --unbuffered 's/^\(.*[^MG]\/s.*\)$/%{F${polybarColors.foreground}}\1%{F-}/'
    '';
  };

  humanDuration = pkgs.writeShellApplication {
    name = "polybar-human-duration";
    runtimeInputs = [ pkgs.gnused ];
    text = ''
      dur_to_dateadd() {
        sed -E '
          /^P/!{
            s/.*/ERROR: Invalid input - it has to start with P: "&"/
            q1
          }
          s/^P//
          s/$/\x01/
          s/^([0-9]*([,.][0-9]*)?)Y(.*)/\3\1year /
          s/^([0-9]*([,.][0-9]*)?)M(.*)/\3\1month /
          s/^([0-9]*([,.][0-9]*)?)D(.*)/\3\1day /
          /^T/{
            s///
            s/^([0-9]*([,.][0-9]*)?)H(.*)/\3\1h /
            s/^([0-9]*([,.][0-9]*)?)M(.*)/\3\1m/
            s/^([0-9]*([,.][0-9]*)?)S(.*)/\3/
          }
          /^\x01/!{
            s/\x01.*//
            s/.*/ERROR: Unparsable input: "&"/
            q1
          }
          s///
          s/,/./g
        ' <<< "$1"
      }

      dur_to_dateadd "$1"
    '';
  };

  timewarriorStatus = pkgs.writeShellApplication {
    name = "polybar-timewarrior";
    runtimeInputs = [ pkgs.timewarrior ];
    text = ''
      echo "$(timew get dom.active.tags.1) $(${lib.getExe humanDuration} "$(timew get dom.active.duration)")"
    '';
  };

  heartRateStatus =
    let
      heartRateScript = ./heart-rate.rs;
    in
    pkgs.writeShellApplication {
      name = "polybar-heart-rate";
      runtimeInputs = [
        pkgs.cargo
        pkgs.coreutils
        pkgs.gcc
        pkgs.pkg-config
        pkgs.rust-script
        pkgs.rustc
      ];
      text = ''
        log="''${XDG_CACHE_HOME:-$HOME/.cache}/polybar-heart-rate.log"
        mkdir -p "$(dirname "$log")"

        export PKG_CONFIG_PATH="${pkgs.dbus.dev}/lib/pkgconfig:${pkgs.bluez.dev}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
        export LD_LIBRARY_PATH="${pkgs.dbus.lib}/lib:${pkgs.bluez}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

        while true; do
          echo ""
          set +o pipefail
          rust-script ${heartRateScript} ${lib.escapeShellArg garminHeartRateAddress} 2>>"$log" \
            | while IFS= read -r bpm; do
                case "$bpm" in
                  "" | *[!0-9]*)
                    ;;
                  *)
                    if [ "$bpm" -gt 65 ]; then
                      echo "%{F${polybarColors.foregroundAlt}}hr %{F-}%{F${polybarColors.warn}}%{T2}$bpm%{T-}%{F-}"
                    else
                      echo "%{F${polybarColors.foregroundAlt}}hr %{F-}$bpm"
                    fi
                    ;;
                esac
              done
          set -o pipefail

          echo ""
          printf '%s heart-rate stream stopped, retrying\n' "$(date --iso-8601=seconds)" >> "$log"
          sleep 10
        done
      '';
    };
in
{
  # Generated from the previous Polybar INI. Home Manager documents
  # services.polybar.settings as the Nix-native form for Polybar config.
  "bar/default" = {
    "monitor" = "\${env:MONITOR:eDP-1}";
    "width" = "100%";
    "height" = statusbarHeight;
    "fixed-center" = false;
    "background" = "\${colors.background}";
    "foreground" = "\${colors.foreground}";
    "font-0" = statusbarFont "Regular" 2;
    "font-1" = statusbarFont "Bold" 2;
    "font-2" = statusbarClockFont "Regular" 3;
    "modules-left" = "hlwm-tags xwindow";
    "modules-center" = "";
    "modules-right" = lib.concatStringsSep " " [
      "process"
      "docker"
      "cpu"
      "cpufreq"
      "freqmenu"
      "temperature"
      "memory"
      "filesystem"
      "ioread"
      "iowrite"
      "eth"
      "wifi"
      "volume"
      "battery"
      "heart-rate"
      "timewarrior"
      "tray"
      "date"
      "time"
    ];
    "module-margin-left" = 1;
    "module-margin-right" = 2;
    "padding-right" = 1;
  };

  "settings" = {
    "screenchange-reload" = true;
  };

  "colors" = {
    "background" = polybarColors.background;
    "foreground" = polybarColors.foreground;
    "foreground-alt" = polybarColors.foregroundAlt;
    "warn" = polybarColors.warn;
    "peak" = polybarColors.peak;
  };

  "base" = {
    "ramp-base-0" = "%{F${polybarColors.foregroundAlt}}▁%{F-}";
    "ramp-base-1" = "▂";
    "ramp-base-2" = "▃";
    "ramp-base-3" = "▄";
    "ramp-base-4" = "▅";
    "ramp-base-5" = "▆";
    "ramp-base-6" = "▇";
    "ramp-base-7" = "%{F${polybarColors.peak}}█%{F-}";
    "ramp-warn-0" = "▁";
    "ramp-warn-1" = "▂";
    "ramp-warn-2" = "▃";
    "ramp-warn-3" = "▄";
    "ramp-warn-4" = "▅";
    "ramp-warn-5" = "▆";
    "ramp-warn-6" = "▇";
    "ramp-warn-7" = "█";
  };

  "module/filesystem" = {
    "type" = "internal/fs";
    "warn-percentage" = 99;
    "mount-0" = "/";
    "interval" = 30;
    "fixed-values" = true;
    "spacing" = 4;
    "format-mounted" = "<label-mounted>";
    "format-warn" = "<label-warn>";
    "format-unmounted" = "<label-unmounted>";
    "label-mounted" = "%mountpoint% %free%";
    "label-warn" = "%mountpoint% %free%";
    "label-warn-foreground" = "\${colors.warn}";
  };

  "module/ewmh" = {
    "type" = "internal/xworkspaces";
  };

  "module/tray" = {
    "type" = "internal/tray";
    "tray-spacing" = "8px";
    "tray-size" = "75%";
  };

  "module/i3" = {
    "type" = "internal/i3";
    "pin-workspaces" = true;
    "show-urgent" = true;
    "strip-wsnumbers" = true;
    "index-sort" = true;
    "enable-click" = true;
    "enable-scroll" = false;
    "wrapping-scroll" = false;
    "reverse-scroll" = false;
    "fuzzy-match" = true;
  };

  "module/hlwm-tags" = {
    "type" = "custom/script";
    "exec" = "${lib.getExe hlwmTags} \${MONITOR_HLWM:-0}";
    "exec-if" = "${herbstclient} version";
    "tail" = true;
  };

  "module/workspaces-xmonad" = {
    "type" = "custom/script";
    "exec" = "${coreutils}/tail -F /tmp/.xmonad-workspace-log";
    "exec-if" = "${coreutils}/test -a /tmp/.xmonad-workspace-log";
    "tail" = true;
  };

  "module/xwindow" = {
    "type" = "internal/xwindow";
    "label" = "%{A2:${xdotool} getwindowfocus windowkill:}%title:0:49:...%%{A}";
  };

  "module/cpu" = {
    "type" = "internal/cpu";
    "interval" = 2;
    "format" = "<ramp-coreload>";
    "format-prefix" = "cpu ";
    "format-prefix-foreground" = "\${colors.foreground-alt}";
    "ramp-coreload-0" = "\${base.ramp-base-0}";
    "ramp-coreload-1" = "\${base.ramp-base-1}";
    "ramp-coreload-2" = "\${base.ramp-base-2}";
    "ramp-coreload-3" = "\${base.ramp-base-3}";
    "ramp-coreload-4" = "\${base.ramp-base-4}";
    "ramp-coreload-5" = "\${base.ramp-base-5}";
    "ramp-coreload-6" = "\${base.ramp-base-6}";
    "ramp-coreload-7" = "\${base.ramp-base-7}";
  };

  "module/process" = {
    "type" = "custom/script";
    "exec" = lib.getExe topProcess;
    "tail" = true;
    "format-foreground" = "\${colors.peak}";
    "format-font" = 2;
  };

  "module/docker" = {
    "type" = "custom/script";
    "exec" = "${docker} ps -q | ${coreutils}/wc -l";
    "exec-if" = "[ -n \"$(${docker} ps -q)\" ]";
    "interval" = 10;
    "format-prefix" = "docker ";
    "format-prefix-foreground" = "\${colors.foreground-alt}";
    "format-foreground" = "\${colors.peak}";
    "click-middle" = "${docker} stop $(${docker} ps -qa)";
  };

  "module/ioread" = {
    "type" = "custom/script";
    "exec" = lib.getExe ioRead;
    "tail" = true;
    "label" = "%output:27%";
    "format-prefix" = "ioread ";
    "format-prefix-foreground" = "\${colors.foreground-alt}";
  };

  "module/iowrite" = {
    "type" = "custom/script";
    "exec" = lib.getExe ioWrite;
    "tail" = true;
    "label" = "%output:27%";
    "format-prefix" = "iowrite ";
    "format-prefix-foreground" = "\${colors.foreground-alt}";
  };

  "module/freqmenu" = {
    "type" = "custom/menu";
    "expand-right" = true;
    "label-open" = "";
    "label-close" = "x";
    "label-separator" = " | ";
    "menu-0-0" = "400MHz";
    "menu-0-0-exec" = "${sudo} ${cpupower} frequency-set -u 400MHz";
    "menu-0-1" = "800MHz";
    "menu-0-1-exec" = "${sudo} ${cpupower} frequency-set -u 800MHz";
    "menu-0-2" = "2GHz";
    "menu-0-2-exec" = "${sudo} ${cpupower} frequency-set -u 2GHz";
    "menu-0-3" = "3GHz";
    "menu-0-3-exec" = "${sudo} ${cpupower} frequency-set -u 3GHz";
    "menu-0-4" = "4GHz";
    "menu-0-4-exec" = "${sudo} ${cpupower} frequency-set -u 4GHz";
    "menu-0-5" = "powersave";
    "menu-0-5-exec" = "${sudo} ${cpupower} frequency-set -g powersave";
    "menu-0-6" = "performance";
    "menu-0-6-exec" = "${sudo} ${cpupower} frequency-set -g performance";
  };

  "module/cpufreq" = {
    "type" = "custom/script";
    "exec" = "${cpupower} frequency-info -fm | ${grep} -oP '(?<=frequency: )([^ ]+ [^ ]+)'";
    "label" = "%output:8...%";
    "interval" = 5;
    "click-left" = "#freqmenu.open.0";
  };

  "module/temperature" = {
    "type" = "internal/temperature";
    "thermal-zone" = 5;
    "interval" = 5;
    "warn-temperature" = 90;
    "format" = "<label>";
    "format-warn" = "<label-warn>";
    "format-warn-font" = 2;
    "label" = "%temperature-c%";
    "label-warn" = "%temperature-c%";
    "label-warn-foreground" = "\${colors.warn}";
    "ramp-foreground" = "\${colors.foreground-alt}";
  };

  "module/memory" = {
    "type" = "internal/memory";
    "interval" = 3;
    "format-prefix" = "mem ";
    "format-prefix-foreground" = "\${colors.foreground-alt}";
    "format" = "<ramp-used><ramp-swap-used>";
    "ramp-used-0" = "\${base.ramp-base-0}";
    "ramp-used-1" = "\${base.ramp-base-1}";
    "ramp-used-2" = "\${base.ramp-base-2}";
    "ramp-used-3" = "\${base.ramp-base-3}";
    "ramp-used-4" = "\${base.ramp-base-4}";
    "ramp-used-5" = "\${base.ramp-base-5}";
    "ramp-used-6" = "\${base.ramp-base-6}";
    "ramp-used-7" = "\${base.ramp-warn-7}";
    "ramp-swap-used-foreground" = "\${colors.warn}";
    "ramp-swap-used-0" = "";
    "ramp-swap-used-1" = "\${base.ramp-warn-1}";
    "ramp-swap-used-2" = "\${base.ramp-warn-2}";
    "ramp-swap-used-3" = "\${base.ramp-warn-3}";
    "ramp-swap-used-4" = "\${base.ramp-warn-4}";
    "ramp-swap-used-5" = "\${base.ramp-warn-5}";
    "ramp-swap-used-6" = "\${base.ramp-warn-6}";
    "ramp-swap-used-7" = "\${base.ramp-warn-7}";
  };

  "module/eth" = {
    "type" = "internal/network";
    "interface" = "enp0s20f0u1";
    "interval" = "3.0";
    "format-connected-prefix" = "eth ";
    "format-connected-prefix-foreground" = "\${colors.foreground-alt}";
    "label-connected" = "▼%downspeed:9%  ▲%upspeed:9%";
    "format-disconnected" = "";
  };

  "module/wifi" = {
    "type" = "internal/network";
    "interface" = "wlp2s0";
    "interval" = "5.0";
    "format-connected" = "<label-connected>";
    "label-connected" = "%essid%  ▼%downspeed:9%  ▲%upspeed:9%";
    "format-disconnected" = "";
    "ramp-signal-0" = "\${base.ramp-base-0}";
    "ramp-signal-1" = "\${base.ramp-base-1}";
    "ramp-signal-2" = "\${base.ramp-base-2}";
    "ramp-signal-3" = "\${base.ramp-base-3}";
    "ramp-signal-4" = "\${base.ramp-base-4}";
    "ramp-signal-foreground" = "\${colors.foreground}";
  };

  "module/ping" = {
    "type" = "custom/script";
    "exec" = "${ping} -i 60 8.8.8.8 | ${awk} -F 'time=' '/time=/ {print $2}'";
    "tail" = true;
    "label" = "%output:7%";
    "format-prefix" = "ping ";
    "format-prefix-foreground" = "\${colors.foreground-alt}";
  };

  "module/volume" = {
    "type" = "internal/alsa";
    "format-prefix" = "%{A1:${pavucontrol} &:}vol%{A} ";
    "format-prefix-foreground" = "\${colors.foreground-alt}";
    "format-volume-prefix" = "\${self.format-prefix}";
    "format-muted-prefix" = "\${self.format-prefix}";
    "format-volume-prefix-foreground" = "\${self.format-prefix-foreground}";
    "format-muted-prefix-foreground" = "\${self.format-prefix-foreground}";
    "format-volume" = "<ramp-volume>";
    "ramp-volume-0" = "\${base.ramp-base-0}";
    "ramp-volume-1" = "\${base.ramp-base-1}";
    "ramp-volume-2" = "\${base.ramp-base-2}";
    "ramp-volume-3" = "\${base.ramp-base-3}";
    "ramp-volume-4" = "\${base.ramp-base-4}";
    "ramp-volume-5" = "\${base.ramp-base-5}";
    "ramp-volume-6" = "\${base.ramp-base-6}";
    "ramp-volume-7" = "\${base.ramp-base-7}";
    "format-muted" = "<label-muted>";
    "label-muted" = "✕";
  };

  "module/battery" = {
    "type" = "internal/battery";
    "battery" = "BAT0";
    "adapter" = "AC0";
    "full-at" = 98;
    "format-prefix-foreground" = "\${colors.foreground-alt}";
    "format-charging-prefix" = "pwr ";
    "format-discharging-prefix" = "bat ";
    "format-full-prefix" = "pwr ";
    "format-charging-prefix-foreground" = "\${self.format-prefix-foreground}";
    "format-discharging-prefix-foreground" = "\${self.format-prefix-foreground}";
    "format-full-prefix-foreground" = "\${self.format-prefix-foreground}";
    "format-charging" = "<ramp-capacity> <label-charging>";
    "format-discharging" = "<ramp-capacity> <label-discharging>";
    "format-full" = "<label-full>";
    "label-charging" = "%time%";
    "label-discharging" = "%time%";
    "time-format" = "%H:%M";
    "ramp-capacity-0" = "%{F${polybarColors.warn}}▁%{F-}";
    "ramp-capacity-1" = "%{F${polybarColors.warn}}▂%{F-}";
    "ramp-capacity-2" = "▃";
    "ramp-capacity-3" = "▄";
    "ramp-capacity-4" = "▅";
    "ramp-capacity-5" = "▆";
    "ramp-capacity-6" = "▇";
    "ramp-capacity-7" = "█";
  };

  "module/timewarrior" = {
    "type" = "custom/script";
    "exec" = lib.getExe timewarriorStatus;
    "exec-if" = "[ \"$(${timew} get dom.active)\" = 1 ]";
    "interval" = 10;
    "format-prefix" = "tw ";
    "format-prefix-foreground" = "\${colors.foreground-alt}";
    "format-foreground" = "\${colors.peak}";
  };

  "module/date" = {
    "type" = "internal/date";
    "interval" = 5;
    "date" = "%Y-%m-%d %a";
    "date-alt" = "%Y-%m-%d W%V";
    "label" = "%date%";
  };

  "module/time" = {
    "type" = "internal/date";
    "interval" = 5;
    "time" = "%H:%M";
    "time-alt" = "%H:%M:%S";
    "label" = "%time%";
    "label-font" = 3;
  };

  "module/heart-rate" = {
    "type" = "custom/script";
    "exec" = lib.getExe heartRateStatus;
    "tail" = true;
    "label" = "%output%";
  };
}
