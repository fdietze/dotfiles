{
  lib,
  pkgs,
  ...
}: let
  empty = lib.hm.gvariant.mkEmptyArray lib.hm.gvariant.type.string;
  doublePairType = lib.hm.gvariant.type.tupleOf [
    lib.hm.gvariant.type.double
    lib.hm.gvariant.type.double
  ];
  variantType = lib.hm.gvariant.type.variant;
  bangkokLocation = lib.hm.gvariant.mkVariant (
    lib.hm.gvariant.mkTuple [
      (lib.hm.gvariant.mkUint32 2)
      (lib.hm.gvariant.mkVariant (
        lib.hm.gvariant.mkTuple [
          "Bangkok"
          "VTBD"
          false
          (lib.hm.gvariant.mkArray doublePairType [
            (lib.hm.gvariant.mkTuple [0.24289166005364171 1.7558012275062955])
          ])
          (lib.hm.gvariant.mkEmptyArray doublePairType)
        ]
      ))
    ]
  );
  berlinLocation = lib.hm.gvariant.mkVariant (
    lib.hm.gvariant.mkTuple [
      (lib.hm.gvariant.mkUint32 2)
      (lib.hm.gvariant.mkVariant (
        lib.hm.gvariant.mkTuple [
          "Berlin"
          "EDDB"
          true
          (lib.hm.gvariant.mkArray doublePairType [
            (lib.hm.gvariant.mkTuple [0.91426163401859872 0.23591034304566436])
          ])
          (lib.hm.gvariant.mkArray doublePairType [
            (lib.hm.gvariant.mkTuple [0.91658875132345297 0.23387411976724018])
          ])
        ]
      ))
    ]
  );
in {
  dconf.settings."org/gnome/desktop/input-sources" = {
    sources = [
      (lib.hm.gvariant.mkTuple ["xkb" "de+neo"])
      # (lib.hm.gvariant.mkTuple ["xkb" "de"])
    ];
    xkb-options = ["altwin:swap_lalt_lwin"];
  };

  programs.gnome-shell = {
    enable = true;
    extensions = [
      {
        package = pkgs.gnomeExtensions.system-monitor;
      }
      {
        package = pkgs.gnomeExtensions.auto-move-windows; # move window to specific workspace x
      }
      {
        package = pkgs.gnomeExtensions.forge; # tiling window manager
      }
      {
        package = pkgs.gnomeExtensions.workspace-buttons-with-app-icons;
      }
    ];
  };

  dconf.settings = {
    "org/gnome/desktop/calendar" = {
      show-weekdate = true;
    };

    "org/gnome/desktop/datetime" = {
      automatic-timezone = true;
    };

    "org/gnome/desktop/interface" = {
      clock-show-weekday = true;
      # color-scheme = "prefer-dark";
      # icon-theme = "Qogir-Dark";
      show-battery-percentage = true;
      text-scaling-factor = 0.99079754601227;
    };

    "org/gnome/desktop/notifications" = {
      show-in-lock-screen = false;
    };

    "org/gnome/desktop/peripherals/mouse" = {
      accel-profile = "default";
      natural-scroll = false;
      speed = 0.19672131147540983;
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = false;
      two-finger-scrolling-enabled = true;
    };

    "org/gnome/desktop/wm/keybindings" = {
      close = ["<Super>q" "<Super>x"];
      cycle-windows = empty;
      cycle-windows-backward = empty;
      maximize = empty;
      minimize = empty;
      move-to-monitor-down = empty;
      move-to-monitor-left = empty;
      move-to-monitor-right = empty;
      move-to-monitor-up = empty;
      move-to-workspace-1 = ["<Shift><Super>1"];
      move-to-workspace-2 = ["<Shift><Super>2"];
      move-to-workspace-3 = ["<Shift><Super>3"];
      move-to-workspace-4 = ["<Shift><Super>4"];
      move-to-workspace-5 = ["<Shift><Super>5"];
      move-to-workspace-6 = ["<Shift><Super>6"];
      move-to-workspace-7 = ["<Shift><Super>7"];
      move-to-workspace-8 = ["<Shift><Super>8"];
      move-to-workspace-9 = ["<Shift><Super>9"];
      move-to-workspace-last = ["<Shift><Super>w"];
      move-to-workspace-left = ["<Shift><Super>v"];
      move-to-workspace-right = ["<Shift><Super>c"];
      switch-applications = empty;
      switch-applications-backward = empty;
      switch-to-workspace-1 = ["<Super>1"];
      switch-to-workspace-2 = ["<Super>2"];
      switch-to-workspace-3 = ["<Super>3"];
      switch-to-workspace-4 = ["<Super>4"];
      switch-to-workspace-5 = ["<Super>5"];
      switch-to-workspace-6 = ["<Super>6"];
      switch-to-workspace-7 = ["<Super>7"];
      switch-to-workspace-8 = ["<Super>8"];
      switch-to-workspace-9 = ["<Super>9"];
      switch-to-workspace-last = ["<Super>w"];
      switch-to-workspace-left = ["<Super>v"];
      switch-to-workspace-right = ["<Super>c"];
      switch-windows = ["<Super>Tab"];
      switch-windows-backward = ["<Shift><Super>Tab"];
      toggle-fullscreen = ["<Super>f"];
      unmaximize = empty;
    };

    "org/gnome/desktop/wm/preferences" = {
      num-workspaces = 9;
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
      logout = ["<Shift><Super>q"];
      next = ["<Super>z"];
      pause = ["<Super>adiaeresis"];
      play = ["<Super>odiaeresis"];
      previous = ["<Super>udiaeresis"];
      reboot = ["<Shift><Control><Super>y"];
      screensaver = ["<Super>Escape"];
      search = ["<Super>y"];
      shutdown = ["<Shift><Control><Super>q"];
      stop = ["<Alt>adiaeresis"];
      volume-down = ["<Control><Super>n"];
      volume-mute = ["<Control><Super>m"];
      volume-up = ["<Control><Super>h"];
      www = ["<Super>j"];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>d";
      command = "alacritty";
      name = "Terminal";
    };

    "org/gnome/shell/keybindings" = {
      switch-to-application-1 = empty;
      switch-to-application-2 = empty;
      switch-to-application-3 = empty;
      switch-to-application-4 = empty;
      switch-to-application-5 = empty;
      switch-to-application-6 = empty;
      switch-to-application-7 = empty;
      switch-to-application-8 = empty;
      switch-to-application-9 = empty;
      toggle-message-tray = empty;
    };

    "org/gnome/mutter/keybindings" = {
      toggle-tiled-left = empty;
      toggle-tiled-right = empty;
    };

    "org/gnome/mutter" = {
      dynamic-workspaces = false;
    };

    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = true;
      night-light-schedule-automatic = false;
      night-light-temperature = lib.hm.gvariant.mkUint32 4290;
    };

    "org/gnome/shell" = {
      favorite-apps = [
        "firefox.desktop"
        "org.gnome.Calendar.desktop"
        "org.gnome.Nautilus.desktop"
        "Alacritty.desktop"
      ];
    };

    "org/gnome/shell/extensions/auto-move-windows" = {
      application-list = ["org.keepassxc.KeePassXC.desktop:8"];
    };

    "org/gnome/shell/extensions/forge" = {
      css-last-update = lib.hm.gvariant.mkUint32 37;
      tiling-mode-enabled = true;
      window-gap-hidden-on-single = true;
      window-gap-size = lib.hm.gvariant.mkUint32 2;
      window-gap-size-increment = lib.hm.gvariant.mkUint32 1;
      workspace-skip-tile = "1";
    };

    "org/gnome/shell/extensions/forge/keybindings" = {
      con-split-horizontal = empty;
      con-split-layout-toggle = empty;
      con-split-vertical = empty;
      con-stacked-layout-toggle = empty;
      con-tabbed-layout-toggle = empty;
      con-tabbed-showtab-decoration-toggle = empty;
      focus-border-toggle = empty;
      mod-mask-mouse-tile = "Super";
      prefs-tiling-toggle = ["<Super>w"];
      window-focus-down = ["<Super>a"];
      window-focus-left = ["<Super>i"];
      window-focus-right = ["<Super>e"];
      window-focus-up = ["<Super>l"];
      window-gap-size-decrease = ["<Control><Super>minus"];
      window-gap-size-increase = ["<Control><Super>plus"];
      window-move-down = ["<Shift><Super>a"];
      window-move-left = ["<Shift><Super>i"];
      window-move-right = ["<Shift><Super>e"];
      window-move-up = ["<Shift><Super>l"];
      window-resize-bottom-decrease = ["<Shift><Super>g"];
      window-resize-bottom-increase = ["<Shift><Super>r"];
      window-resize-left-decrease = ["<Shift><Control><Super>o"];
      window-resize-left-increase = ["<Control><Super>y"];
      window-resize-right-decrease = ["<Shift><Super>n"];
      window-resize-right-increase = ["<Shift><Super>t"];
      window-resize-top-decrease = ["<Shift><Control><Super>u"];
      window-resize-top-increase = ["<Control><Super>i"];
      window-snap-center = ["<Control><Alt>c"];
      window-snap-one-third-left = ["<Control><Alt>d"];
      window-snap-one-third-right = ["<Control><Alt>g"];
      window-snap-two-third-left = ["<Control><Alt>e"];
      window-snap-two-third-right = ["<Control><Alt>t"];
      window-swap-down = ["<Shift><Super>a"];
      window-swap-last-active = ["<Super>Return"];
      window-swap-left = ["<Shift><Super>i"];
      window-swap-right = ["<Shift><Super>e"];
      window-swap-up = ["<Shift><Super>l"];
      window-toggle-always-float = empty;
      window-toggle-float = ["<Super>h"];
      workspace-active-tile-toggle = empty;
    };

    "org/gnome/shell/extensions/workspace-buttons-with-app-icons" = {
      top-bar-height = 20;
      top-bar-indicator-spacing = 2;
      top-bar-move-date-right = true;
      top-bar-override-color = false;
      top-bar-override-height = true;
      top-bar-status-spacing = 2;
      wsb-container-scroll-to-switch-workspace = true;
      wsb-generate-window-icon-timeout = 200;
      wsb-left-click-activates-unfocused-app = true;
      wsb-middle-click-ignores-clicked-workspace = true;
      wsb-right-click-ignores-clicked-workspace = true;
      wsb-ws-app-icon-size = 14;
      wsb-ws-app-icon-spacing = 3;
      wsb-ws-app-icons-desaturate = false;
      wsb-ws-app-icons-wrapper-active-color = "rgba(62, 180, 46, 0.42)";
      wsb-ws-app-icons-wrapper-inactive-color = "rgba(28, 27, 27, 0.75)";
      wsb-ws-app-icons-wrapper-spacing = 3;
      wsb-ws-btn-border-active-color = "rgba(38, 162, 105, 1)";
      wsb-ws-btn-border-inactive-color = "rgba(94, 92, 100, 1)";
      wsb-ws-btn-border-width = 0;
      wsb-ws-btn-roundness = 3;
      wsb-ws-btn-spacing = 2;
      wsb-ws-btn-vert-spacing = 1;
      wsb-ws-num-active-color = "rgba(62, 180, 46, 0.42)";
      wsb-ws-num-font-size = 9;
      wsb-ws-num-inactive-color = "rgba(28, 27, 27, 0.75)";
      wsb-ws-num-show = true;
      wsb-ws-num-spacing = 2;
      window-switcher-popup-show-windows-from-all-monitors = false;
    };

    "org/gnome/shell/weather" = {
      automatic-location = true;
      locations = lib.hm.gvariant.mkArray variantType [bangkokLocation];
    };

    "org/gnome/shell/world-clocks" = {
      locations = lib.hm.gvariant.mkArray variantType [berlinLocation];
    };
  };
}
