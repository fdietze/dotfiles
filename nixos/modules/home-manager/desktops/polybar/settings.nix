{
  lib,
  pkgs,
  polybarColors,
  uiFonts,
  garminHeartRateAddress,
  ...
}: let
  coreutils = "${pkgs.coreutils}/bin";
  cpupower = "${pkgs.linuxPackages.cpupower}/bin/cpupower";
  docker = lib.getExe pkgs.docker;
  grep = lib.getExe pkgs.gnugrep;
  herbstclient = "${pkgs.herbstluftwm}/bin/herbstclient";
  pavucontrol = lib.getExe pkgs.pavucontrol;
  sudo = "/run/wrappers/bin/sudo";
  timew = lib.getExe pkgs.timewarrior;
  xdotool = lib.getExe pkgs.xdotool;
  statusbarFontSize = toString uiFonts.sizes.statusbar;
  statusbarClockFontSize = toString (uiFonts.sizes.statusbar + 5);
  statusbarIconFontSize = toString (uiFonts.sizes.statusbar + 3);
  statusbarHeight = toString (uiFonts.sizes.statusbar * 2 + 4);
  statusbarFont = style: offset: "${uiFonts.monospace.name}:style=${style}:size=${statusbarFontSize};${toString offset}";
  statusbarClockFont = style: offset: "${uiFonts.monospace.name}:style=${style}:size=${statusbarClockFontSize};${toString offset}";
  statusbarIconFont = style: offset: "${uiFonts.icons.name}:style=${style}:size=${statusbarIconFontSize};${toString offset}";
  # Icon names/codepoints come from pkgs.material-design-icons
  # (Templarian/MaterialDesign-Webfont preview.html).
  icons = {
    battery = "󰁹"; # mdi-battery U+F0079
    batteryCharging = "󰂄"; # mdi-battery-charging U+F0084
    calendar = "󰸗"; # mdi-calendar-month U+F0E17
    cpu = "󰘚"; # mdi-chip U+F061A
    docker = "󰡨"; # mdi-docker U+F0868
    download = "󰇚"; # mdi-download U+F01DA
    ethernet = "󰈀"; # mdi-ethernet U+F0200
    filesystem = "󰋊"; # mdi-harddisk U+F02CA
    heartRate = "󰋑"; # mdi-heart U+F02D1, named "favorite" in Material Icons
    memory = "󰍛"; # mdi-memory U+F035B
    muted = "󰖁"; # mdi-volume-off U+F0581
    speed = "󰓅"; # mdi-speedometer U+F04C5
    temperature = "󰔏"; # mdi-thermometer U+F050F
    timewarrior = "󰔛"; # mdi-timer-outline U+F051B
    upload = "󰕒"; # mdi-upload U+F0552
    volume = "󰕾"; # mdi-volume-high U+F057E
    wifi = "󰖩"; # mdi-wifi U+F05A9
  };
  iconPrefix = icon: "%{T4}${icon}%{T-} ";
  volumeIconPrefix = icon: "%{A1:${pavucontrol} &:}%{T4}${icon}%{T-}%{A} ";

  baseSettings = {
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
      "font-3" = statusbarIconFont "Regular" 3;
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
        "io"
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
      # Polybar IPC is disabled by default. Keep it enabled so this systemd
      # managed bar can still be controlled with polybar-msg for restarts,
      # visibility toggles, and future module actions.
      "enable-ipc" = true;
    };

    # Secondary bars run on non-primary monitors. The tray is intentionally not
    # present here: Polybar's tray is session-global, so only one bar instance
    # should own it.
    "bar/secondary" = {
      "inherit" = "bar/default";
      "modules-right" = lib.concatStringsSep " " [
        "process"
        "docker"
        "cpu"
        "cpufreq"
        "freqmenu"
        "temperature"
        "memory"
        "filesystem"
        "io"
        "eth"
        "wifi"
        "volume"
        "battery"
        "heart-rate"
        "timewarrior"
        "date"
        "time"
      ];
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
  };

  workspaceModules = let
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
        focused_fg=${lib.escapeShellArg polybarColors.tagSelectedFg}
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
                echo -n "%{B$urgent_bg F$focused_fg}"
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
  in {
    "module/hlwm-tags" = {
      "type" = "custom/script";
      "exec" = "${lib.getExe hlwmTags} \${MONITOR_HLWM:-0}";
      "exec-if" = "${herbstclient} version";
      "tail" = true;
    };

    "module/xwindow" = {
      "type" = "internal/xwindow";
      "label" = "%{A2:${xdotool} getwindowfocus windowkill:}%title:0:49:...%%{A}";
    };
  };

  processModule = let
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
  in {
    "module/process" = {
      "type" = "custom/script";
      "exec" = lib.getExe topProcess;
      "tail" = true;
      "format-foreground" = "\${colors.peak}";
      "format-font" = 2;
    };
  };

  dockerModule = {
    "module/docker" = {
      "type" = "custom/script";
      "exec" = "${docker} ps -q | ${coreutils}/wc -l";
      "exec-if" = "[ -n \"$(${docker} ps -q)\" ]";
      "interval" = 10;
      "format-prefix" = iconPrefix icons.docker;
      "format-prefix-foreground" = "\${colors.foreground-alt}";
      "format-foreground" = "\${colors.peak}";
      "click-middle" = "${docker} stop $(${docker} ps -qa)";
    };
  };

  cpuModules = {
    "module/cpu" = {
      "type" = "internal/cpu";
      "interval" = 2;
      "format" = "<ramp-coreload>";
      # "format-prefix" = iconPrefix icons.cpu;
      # "format-prefix-foreground" = "\${colors.foreground-alt}";
      "ramp-coreload-0" = "\${base.ramp-base-0}";
      "ramp-coreload-1" = "\${base.ramp-base-1}";
      "ramp-coreload-2" = "\${base.ramp-base-2}";
      "ramp-coreload-3" = "\${base.ramp-base-3}";
      "ramp-coreload-4" = "\${base.ramp-base-4}";
      "ramp-coreload-5" = "\${base.ramp-base-5}";
      "ramp-coreload-6" = "\${base.ramp-base-6}";
      "ramp-coreload-7" = "\${base.ramp-base-7}";
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
      # "format-prefix" = iconPrefix icons.speed;
      # "format-prefix-foreground" = "\${colors.foreground-alt}";
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
      # "format-prefix" = iconPrefix icons.temperature;
      # "format-prefix-foreground" = "\${colors.foreground-alt}";
      "format-warn" = "<label-warn>";
      # "format-warn-prefix" = iconPrefix icons.temperature;
      # "format-warn-prefix-foreground" = "\${colors.warn}";
      "format-warn-font" = 2;
      "label" = "%temperature-c%";
      "label-warn" = "%temperature-c%";
      "label-warn-foreground" = "\${colors.warn}";
      "ramp-foreground" = "\${colors.foreground-alt}";
    };
  };

  memoryModule = {
    "module/memory" = {
      "type" = "internal/memory";
      "interval" = 3;
      # "format-prefix" = iconPrefix icons.memory;
      # "format-prefix-foreground" = "\${colors.foreground-alt}";
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
  };

  filesystemModule = {
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
  };

  ioModules = let
    diskIo = pkgs.writeShellApplication {
      name = "polybar-disk-io";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        is_physical_disk() {
          case "$1" in
            loop* | ram* | zram* | sr* | dm-* | md*)
              return 1
              ;;
            *)
              return 0
              ;;
          esac
        }

        read_sectors() {
          local read_sectors=0
          local written_sectors=0
          local dev stat sectors_read sectors_written rest

          for stat in /sys/block/*/stat; do
            dev="''${stat%/stat}"
            dev="''${dev##*/}"
            is_physical_disk "$dev" || continue

            read -r _ _ sectors_read _ _ _ sectors_written rest < "$stat"
            read_sectors=$((read_sectors + sectors_read))
            written_sectors=$((written_sectors + sectors_written))
          done

          printf '%s %s\n' "$read_sectors" "$written_sectors"
        }

        format_rate() {
          local bytes=$1
          local tenths
          local unit

          if [ "$bytes" -ge 1073741824 ]; then
            tenths=$(((bytes * 10 + 536870912) / 1073741824))
            unit=G/s
          elif [ "$bytes" -ge 1048576 ]; then
            tenths=$(((bytes * 10 + 524288) / 1048576))
            unit=M/s
          else
            tenths=$(((bytes * 10 + 512) / 1024))
            unit=K/s
          fi

        # Keep the numeric field fixed-width so the bar does not jump around
        # while still using the smallest useful throughput unit.
        rate=$(printf '%3d.%d%s' "$((tenths / 10))" "$((tenths % 10))" "$unit")

        if [ "$bytes" -gt 1048576 ]; then
          printf '%%{F${polybarColors.peak}}%s%%{F-}' "$rate"
        else
          printf '%s' "$rate"
        fi
        }

        read -r prev_read prev_written < <(read_sectors)

        while true; do
          sleep 5
          read -r current_read current_written < <(read_sectors)

          read_delta=$((current_read - prev_read))
          written_delta=$((current_written - prev_written))
          prev_read=$current_read
          prev_written=$current_written

          if [ "$read_delta" -lt 0 ]; then
            read_delta=0
          fi
          if [ "$written_delta" -lt 0 ]; then
            written_delta=0
          fi

          # Linux reports disk sectors as 512-byte units for these counters.
          # Keep R/W dimmed as labels and highlight active throughput with the
          # same peak color used by the active Timewarrior module.
          printf '%%{F${polybarColors.foregroundAlt}}R%%{F-} %s %%{F${polybarColors.foregroundAlt}}W%%{F-} %s\n' \
            "$(format_rate "$((read_delta * 512))")" \
            "$(format_rate "$((written_delta * 512))")"
        done
      '';
    };
  in {
    "module/io" = {
      "type" = "custom/script";
      "exec" = lib.getExe diskIo;
      "tail" = true;
      "label" = "%output%";
    };
  };

  networkModules = let
    networkRates = pkgs.writeShellApplication {
      name = "polybar-network-rates";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.networkmanager
      ];
      text = ''
        interface=$1
        icon=$2
        show_essid=$3
        interval=$4
        sysfs="/sys/class/net/$interface"

        connected() {
          if [ ! -d "$sysfs/statistics" ]; then
            return 1
          fi

          if [ -r "$sysfs/carrier" ]; then
            [ "$(cat "$sysfs/carrier" 2>/dev/null)" = 1 ]
          else
            [ "$(cat "$sysfs/operstate" 2>/dev/null)" = up ]
          fi
        }

        read_bytes() {
          printf '%s %s\n' \
            "$(cat "$sysfs/statistics/rx_bytes" 2>/dev/null)" \
            "$(cat "$sysfs/statistics/tx_bytes" 2>/dev/null)"
        }

        format_rate() {
          local bytes=$1
          local tenths
          local unit
          local rate

          if [ "$bytes" -ge 1073741824 ]; then
            tenths=$(((bytes * 10 + 536870912) / 1073741824))
            unit=G/s
          elif [ "$bytes" -ge 1048576 ]; then
            tenths=$(((bytes * 10 + 524288) / 1048576))
            unit=M/s
          else
            tenths=$(((bytes * 10 + 512) / 1024))
            unit=K/s
          fi

          # Match the disk I/O module's highlight threshold and omit the "B"
          # to keep the network module compact.
          rate=$(printf '%3d.%d%s' "$((tenths / 10))" "$((tenths % 10))" "$unit")

          if [ "$bytes" -gt 1048576 ]; then
            printf '%%{F${polybarColors.peak}}%s%%{F-}' "$rate"
          else
            printf '%s' "$rate"
          fi
        }

        essid() {
          if [ "$show_essid" = 1 ]; then
            nmcli -t -f active,ssid dev wifi \
              | grep -E '^yes' \
              | cut -d: -f2 \
              || true
          fi
          return 0
        }

        while true; do
          if connected; then
            read -r prev_rx prev_tx < <(read_bytes)
            sleep "$interval"

            if connected; then
              read -r current_rx current_tx < <(read_bytes)
              rx_delta=$((current_rx - prev_rx))
              tx_delta=$((current_tx - prev_tx))

              if [ "$rx_delta" -lt 0 ]; then
                rx_delta=0
              fi
              if [ "$tx_delta" -lt 0 ]; then
                tx_delta=0
              fi

              prefix="%{F${polybarColors.foregroundAlt}}%{T4}$icon%{T-}%{F-} "
              ssid=$(essid)
              if [ -n "$ssid" ]; then
                prefix="$prefix$ssid  "
              fi

              printf '%s%%{F${polybarColors.foregroundAlt}}%%{T4}${icons.download}%%{T-}%%{F-}%s  %%{F${polybarColors.foregroundAlt}}%%{T4}${icons.upload}%%{T-}%%{F-}%s\n' \
                "$prefix" \
                "$(format_rate "$((rx_delta / interval))")" \
                "$(format_rate "$((tx_delta / interval))")"
            else
              echo ""
            fi
          else
            echo ""
            sleep "$interval"
          fi
        done
      '';
    };
  in {
    "module/eth" = {
      "type" = "custom/script";
      "exec" = "${lib.getExe networkRates} enp0s20f0u1 ${lib.escapeShellArg icons.ethernet} 0 3";
      "tail" = true;
      "label" = "%output%";
    };

    "module/wifi" = {
      "type" = "custom/script";
      "exec" = "${lib.getExe networkRates} wlp2s0 ${lib.escapeShellArg icons.wifi} 1 5";
      "tail" = true;
      "label" = "%output%";
    };
  };

  volumeModule = {
    "module/volume" = {
      "type" = "internal/pulseaudio";
      "format-volume-prefix" = volumeIconPrefix icons.volume;
      "format-muted-prefix" = volumeIconPrefix icons.muted;
      "format-volume-prefix-foreground" = "\${colors.foreground-alt}";
      "format-muted-prefix-foreground" = "\${colors.foreground-alt}";
      "format-volume" = "<ramp-volume>";
      "ramp-volume-0" = "\${base.ramp-base-0}";
      "ramp-volume-1" = "\${base.ramp-base-1}";
      "ramp-volume-2" = "\${base.ramp-base-2}";
      "ramp-volume-3" = "\${base.ramp-base-3}";
      "ramp-volume-4" = "\${base.ramp-base-4}";
      "ramp-volume-5" = "\${base.ramp-base-5}";
      "ramp-volume-6" = "\${base.ramp-base-6}";
      "ramp-volume-7" = "\${base.ramp-base-7}";
      # Keep the muted module visible while staying ramp-only/no percentage.
      "format-muted" = "<label-muted>";
      "label-muted" = "\${base.ramp-base-0}";
    };
  };

  batteryModule = {
    "module/battery" = {
      "type" = "internal/battery";
      "battery" = "BAT0";
      "adapter" = "AC0";
      "full-at" = 98;
      # Polybar's internal/battery low state supports animation-low; use a
      # same-width blank frame so low battery visibly blinks without shifting
      # neighbouring modules.
      "low-at" = 15;
      "format-prefix-foreground" = "\${colors.foreground-alt}";
      "format-charging-prefix" = iconPrefix icons.batteryCharging;
      "format-full-prefix" = iconPrefix icons.batteryCharging;
      "format-charging-prefix-foreground" = "\${self.format-prefix-foreground}";
      "format-full-prefix-foreground" = "\${self.format-prefix-foreground}";
      # Capacity icons carry the battery state more directly than a generic
      # battery prefix plus block ramp. Full stays compact: icon only.
      "format-charging" = "<label-charging>";
      "format-discharging" = "<ramp-capacity> <label-discharging>";
      "format-low" = "<animation-low> <label-low>";
      "format-full" = "";
      "label-charging" = "%time%";
      "label-discharging" = "%time%";
      "label-low" = "%time%";
      "time-format" = "%H:%M";
      "animation-low-0" = "%{F${polybarColors.warn}}󰂎%{F-}";
      "animation-low-1" = " ";
      "animation-low-framerate" = 750;
      "ramp-capacity-0" = "%{F${polybarColors.warn}}󰂎%{F-}"; # mdi-battery-outline U+F008E
      "ramp-capacity-1" = "%{F${polybarColors.warn}}󰁺%{F-}"; # mdi-battery-10 U+F007A
      "ramp-capacity-2" = "󰁻"; # mdi-battery-20 U+F007B
      "ramp-capacity-3" = "󰁽"; # mdi-battery-40 U+F007D
      "ramp-capacity-4" = "󰁿"; # mdi-battery-60 U+F007F
      "ramp-capacity-5" = "󰂀"; # mdi-battery-70 U+F0080
      "ramp-capacity-6" = "󰂁"; # mdi-battery-80 U+F0081
      "ramp-capacity-7" = "󰁹"; # mdi-battery U+F0079
    };
  };

  timeModules = let
    humanDuration = pkgs.writeShellApplication {
      name = "polybar-human-duration";
      runtimeInputs = [pkgs.gnused];
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
      runtimeInputs = [pkgs.timewarrior];
      text = ''
        echo "$(timew get dom.active.tags.1) $(${lib.getExe humanDuration} "$(timew get dom.active.duration)")"
      '';
    };
  in {
    "module/timewarrior" = {
      "type" = "custom/script";
      "exec" = lib.getExe timewarriorStatus;
      "exec-if" = "[ \"$(${timew} get dom.active)\" = 1 ]";
      "interval" = 10;
      "format-prefix" = iconPrefix icons.timewarrior;
      "format-prefix-foreground" = "\${colors.foreground-alt}";
      "format-foreground" = "\${colors.peak}";
    };

    "module/date" = {
      "type" = "internal/date";
      "interval" = 5;
      "date" = "%Y-%m-%d %a";
      "date-alt" = "%Y-%m-%d W%V";
      # "format-prefix" = iconPrefix icons.calendar;
      # "format-prefix-foreground" = "\${colors.foreground-alt}";
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
  };

  heartRateModule = let
    heartRateScript = ./heart-rate.rs;
    heartRateStatus = pkgs.writeShellApplication {
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
        # Keep using rust-script so heart-rate.rs stays directly runnable as a
        # CLI while iterating on Bluetooth behavior outside the Nix build.
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
                        echo "%{F${polybarColors.foregroundAlt}}${iconPrefix icons.heartRate}%{F-}%{F${polybarColors.warn}}%{T2}$bpm%{T-}%{F-}"
                      else
                        echo "%{F${polybarColors.foregroundAlt}}${iconPrefix icons.heartRate}%{F-}$bpm"
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
  in {
    "module/heart-rate" = {
      "type" = "custom/script";
      "exec" = lib.getExe heartRateStatus;
      "tail" = true;
      "label" = "%output%";
    };
  };

  trayModule = {
    "module/tray" = {
      "type" = "internal/tray";
      # Polybar can only hint tray colors via _NET_SYSTEM_TRAY_COLORS; many
      # apps still choose their own icon assets, so GTK/Qt icon theme settings
      # and per-app tray options remain the source of truth for stubborn icons.
      # See Polybar's internal/tray documentation for tray-foreground.
      "tray-background" = polybarColors.background;
      "tray-foreground" = polybarColors.foregroundAlt;
      "tray-spacing" = "8px";
      "tray-size" = "75%";
    };
  };
in
  baseSettings
  // workspaceModules
  // processModule
  // dockerModule
  // cpuModules
  // memoryModule
  // filesystemModule
  // ioModules
  // networkModules
  // volumeModule
  // batteryModule
  // timeModules
  // heartRateModule
  // trayModule
