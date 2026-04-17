{
  desktop ? "gnome",
  theme,
  lib,
  pkgs,
  config,
  ...
}: let
  empty = lib.hm.gvariant.mkEmptyArray lib.hm.gvariant.type.string;
  currentThemeTarget = "theme-${theme}.target";
  themeSwitchCommand = mode: "${config.home.profileDirectory}/bin/theme-${mode}";
  gnomeColorScheme =
    if theme == "light"
    then "prefer-light"
    else "prefer-dark";
  applyGnomeTheme = pkgs.writeShellScript "apply-gnome-theme-${theme}" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    if [[ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
      exit 0
    fi

    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme ${lib.escapeShellArg gnomeColorScheme}
  '';
  paperwmExtensionId = "paperwm@paperwm.github.com";
  paperwmLatest = pkgs.gnomeExtensions.paperwm.overrideAttrs (_: {
    version = "49.0.2";
    src = pkgs.fetchFromGitHub {
      owner = "paperwm";
      repo = "PaperWM";
      rev = "8e038d0aee5dd71199ec4bcd16b1964a6b519772";
      sha256 = "01kcw40kshgwspxkpmd5l519dra5j6xpqc0g666blqn95glxnzkf";
    };
  });
  doublePairType = lib.hm.gvariant.type.tupleOf [
    lib.hm.gvariant.type.double
    lib.hm.gvariant.type.double
  ];
  variantType = lib.hm.gvariant.type.variant;
  workspaceButtonsWithAppIconsPatched = pkgs.gnomeExtensions.workspace-buttons-with-app-icons.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        substituteInPlace "$out/share/gnome-shell/extensions/workspace-buttons-with-app-icons@miro011.github.com/globals.js" \
          --replace-fail "    stylesheetFile.replace_contents(" "    try { stylesheetFile.replace_contents(" \
          --replace-fail "    );" "    ); } catch (error) { console.log('Workspace Buttons With App Icons: keeping packaged stylesheet.css because runtime update failed: ' + error.message); }"
      '';
  });
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
in
  lib.mkIf (desktop == "gnome") {
  home.packages = with pkgs; [
    dconf-editor # gnome settings gui
    xr-linux-driver
    breezy-gnome # vr displays
  ];

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
      {package = pkgs.gnomeExtensions.system-monitor;}
      {package = workspaceButtonsWithAppIconsPatched;}
      {package = pkgs.gnomeExtensions.no-overview;}
      {package = pkgs.gnomeExtensions.disable-workspace-switcher;}
      {package = pkgs.gnomeExtensions.system-monitor;}
      {
        # scrollable tiling window manager
        package = paperwmLatest;
      }
    ];
  };

  dconf.settings = {
    "org/gnome/gnome-session" = {
      logout-prompt = false;
    };

    "org/gnome/desktop/calendar" = {
      show-weekdate = true;
    };

    "org/gnome/desktop/datetime" = {
      automatic-timezone = true;
    };

    "org/gnome/desktop/interface" = {
      clock-show-weekday = true;
      color-scheme = lib.mkForce gnomeColorScheme;
      # icon-theme = "Qogir-Dark";
      show-battery-percentage = true;
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
      speed = 0.27196652719665271;
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
      switch-to-workspace-last = empty;
      switch-to-workspace-left = ["<Super>v"];
      switch-to-workspace-right = ["<Super>c"];
      switch-windows = ["<Super>Tab"];
      switch-windows-backward = ["<Shift><Super>Tab"];
      toggle-fullscreen = empty;
      unmaximize = empty;
    };

    "org/gnome/desktop/wm/preferences" = {
      mouse-button-modifier = "disabled";
      num-workspaces = 9;
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom7/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom8/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom9/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom10/"
      ];
      logout = ["<Shift><Super>q"];
      next = ["<Super>z"];
      pause = empty;
      play = ["<Super>odiaeresis"];
      previous = ["<Super>udiaeresis"];
      reboot = ["<Shift><Control><Super>y"];
      rfkill-bluetooth = ["<Super>b"];
      screensaver = empty;
      search = ["<Super>y"];
      shutdown = ["<Shift><Control><Super>q"];
      stop = ["<Super>p"];
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

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      binding = "<Super>Escape";
      command = "loginctl lock-session";
      name = "Lock Screen";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2" = {
      binding = "<Super>k";
      command = "${pkgs.xorg.xkill}/bin/xkill";
      name = "XKill";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3" = {
      binding = "<Super>adiaeresis";
      command = "${pkgs.playerctl}/bin/playerctl play-pause";
      name = "Play Pause";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4" = {
      binding = "<Control><Super>g";
      command = "${pkgs.brightnessctl}/bin/brightnessctl set +5%";
      name = "Brightness Up";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5" = {
      binding = "<Control><Super>r";
      command = "${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
      name = "Brightness Down";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom6" = {
      binding = "<Control><Shift><Super>g";
      command = "${pkgs.brightnessctl}/bin/brightnessctl set +1%";
      name = "Brightness Up Fine";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom7" = {
      binding = "<Control><Shift><Super>r";
      command = "${pkgs.brightnessctl}/bin/brightnessctl set 1%-";
      name = "Brightness Down Fine";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom8" = {
      binding = "<Shift><Super>y";
      command = "${pkgs.bash}/bin/bash -lc 'gnome-extensions disable ${paperwmExtensionId}; sleep 1; gnome-extensions enable ${paperwmExtensionId}'";
      name = "Restart PaperWM";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom9" = {
      binding = "<Control><Super>k";
      command = themeSwitchCommand "light";
      name = "Theme Light";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom10" = {
      binding = "<Control><Super>s";
      command = themeSwitchCommand "dark";
      name = "Theme Dark";
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

    "org/gnome/settings-daemon/plugins/power" = {
      power-saver-profile-on-low-battery = true;
      sleep-inactive-ac-type = "nothing";
    };

    "org/gnome/shell" = {
      disable-user-extensions = false;
      disabled-extensions = lib.mkForce ["tilingshell@ferrarodomenico.com"];
      enabled-extensions = lib.mkForce [
        "system-monitor@gnome-shell-extensions.gcampax.github.com"
        "workspace-buttons-with-app-icons@miro011.github.com"
        "no-overview@fthx"
        "disable-workspace-switcher@jbradaric.me"
        paperwmExtensionId
      ];
      favorite-apps = [
        "firefox.desktop"
        "org.gnome.Calendar.desktop"
        "org.gnome.Nautilus.desktop"
        "Alacritty.desktop"
      ];
    };

    "org/gnome/shell/app-switcher" = {
      current-workspace-only = true;
    };

    "org/gnome/shell/extensions/paperwm" = {
      winprops = [
        ''{"wm_class":"KeePassXC","spaceIndex":7,"focus":true}''
      ];
    };

    "org/gnome/shell/extensions/paperwm/keybindings" = {
      new-window = empty;
      live-alt-tab = empty;
      live-alt-tab-backward = empty;
      live-alt-tab-scratch = empty;
      live-alt-tab-scratch-backward = empty;

      previous-workspace = ["<Super>w"];
      previous-workspace-backward = empty;
      move-previous-workspace = empty;
      move-previous-workspace-backward = empty;
      switch-down-workspace = empty;
      switch-up-workspace = empty;
      switch-down-workspace-from-all-monitors = empty;
      switch-up-workspace-from-all-monitors = empty;
      move-down-workspace = empty;
      move-up-workspace = empty;
      toggle-top-and-position-bar = empty;
      toggle-top-bar = empty;
      toggle-position-bar = empty;

      switch-left = ["<Super>i"];
      switch-right = ["<Super>e"];
      switch-up = ["<Super>l"];
      switch-down = ["<Super>a"];
      switch-next = empty;
      switch-previous = empty;
      switch-next-loop = empty;
      switch-previous-loop = empty;
      switch-right-loop = empty;
      switch-left-loop = empty;
      switch-up-loop = empty;
      switch-down-loop = empty;
      switch-global-right = empty;
      switch-global-left = empty;
      switch-global-up = empty;
      switch-global-down = empty;
      switch-up-or-else-workspace = empty;
      switch-down-or-else-workspace = empty;
      switch-first = empty;
      switch-second = empty;
      switch-third = empty;
      switch-fourth = empty;
      switch-fifth = empty;
      switch-sixth = empty;
      switch-seventh = empty;
      switch-eighth = empty;
      switch-ninth = empty;
      switch-tenth = empty;
      switch-eleventh = empty;
      switch-last = empty;

      move-left = ["<Shift><Super>i"];
      move-right = ["<Shift><Super>e"];
      move-up = ["<Shift><Super>l"];
      move-down = ["<Shift><Super>a"];

      drift-left = empty;
      drift-right = empty;

      switch-monitor-left = ["<Super>u"];
      switch-monitor-right = ["<Super>o"];
      switch-monitor-above = empty;
      switch-monitor-below = empty;
      move-monitor-left = ["<Shift><Super>u"];
      move-monitor-right = ["<Shift><Super>o"];
      move-monitor-above = empty;
      move-monitor-below = empty;
      move-space-monitor-right = empty;
      move-space-monitor-left = empty;
      move-space-monitor-above = empty;
      move-space-monitor-below = empty;
      swap-monitor-right = empty;
      swap-monitor-left = empty;
      swap-monitor-above = empty;
      swap-monitor-below = empty;

      open-window-position-up = ["<Super>g"];
      open-window-position-down = ["<Super>r"];
      open-window-position-left = ["<Super>n"];
      open-window-position-right = ["<Super>t"];
      open-window-position-start = empty;
      open-window-position-end = empty;

      resize-h-dec = ["<Shift><Super>g"];
      resize-h-inc = ["<Shift><Super>r"];
      resize-w-dec = ["<Shift><Super>n"];
      resize-w-inc = ["<Shift><Super>t"];

      cycle-width = empty;
      cycle-width-backwards = empty;
      cycle-height = empty;
      cycle-height-backwards = empty;

      switch-focus-mode = empty;
      switch-open-window-position = empty;
      center-horizontally = ["<Control><Super>c"];
      center-vertically = ["<Control><Super>v"];
      center = empty;
      take-window = empty;
      activate-window-under-cursor = empty;
      toggle-maximize-width = empty;
      paper-toggle-fullscreen = ["<Super>f"];
      close-window = ["<Super>q" "<Super>x"];

      toggle-scratch-window = empty;
      toggle-scratch-layer = ["<Alt><Shift><Super>Escape"];
      toggle-scratch = ["<Alt><Control><Super>Escape"];

      slurp-in = empty;
      barf-out = empty;
      barf-out-active = empty;
    };

    "org/gnome/shell/extensions/workspace-buttons-with-app-icons" = {
      # top-bar-height = 20;
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

  systemd.user.services."gnome-interface-${theme}" = {
    Unit = {
      Description = "Apply GNOME ${theme} theme";
      After = ["graphical-session.target"];
      PartOf = [currentThemeTarget];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${applyGnomeTheme}";
    };
    Install.WantedBy = [currentThemeTarget];
  };
}
