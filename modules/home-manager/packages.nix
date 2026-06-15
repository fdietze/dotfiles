{pkgs, ...}: {
  home.packages =
    (with pkgs; [
      # command line fu
      # https://github.com/ibraheemdev/modern-unix
      pistol # file preview
      feh # image viewer
      playerctl # control media players, like spotify, vlc via cli / keybindings
      pamixer # control pulseaudio via cli / keybindings
      autorandr # automatic monitor profiles
      xsel # clipboard
      xclip # clipboard
      imagemagick
      ffmpeg-full
      mediainfo
      xcolor # simple color picker
      ngrok # remote http tunnel
      chafa # preview images
      dragon-drop # file drag and drop initiated from command line
      pandoc # convert document formats
      texliveSmall # required by pandoc
      diff-so-fancy # diff viewer. TODO: replace with delta
      # curl-impersonate # curl mocking a real browser
      espeak # text to speech
      whisper-cpp # audio transcription
      alsa-utils # audo recording
      nrfconnect # bluetooth ble
      overskride # on-demand bluetooth manager; no always-running tray applet
      typst # modern latex alternative
      pulsemixer # audio mixer tui
      bluetuith # bluetooth tui

      arandr # manage monitors
      wdisplays # manage monitors (wayland/wlroots)

      # system tools
      pciutils
      usbutils
      hdparm
      gparted
      exfatprogs
      ntfs3g
      ntfsprogs
      testdisk
      lm_sensors
      linuxPackages.cpupower
      xkill
      wirelesstools
      xbacklight
      acpi
      samba
      cifs-utils
      # mtpfs
      jmtpfs
      smartmontools # hard drive diagnostics

      # defaults
      pavucontrol
      mimeo
      xdotool
      macchanger
      ghostscript # pdf (nvim)
      mermaid-cli # mermaid diagrams
      # development
      # earthly # better Dockerfiles
      visualvm # jvm profiling
      coursier # scala package manager, used to install metals
      # helix # modal editor
      devenv # nix based dev environments
      # code-cursor # ai code editor
      # antigravity-fhs # ai code editor from google
      # cursor-cli # ai coding agent
      meld # git conflict resolution ui

      # themeing
      (polybar.override {
        # PipeWire provides the PulseAudio-compatible server; Polybar needs this
        # build flag for the native internal/pulseaudio volume module.
        pulseSupport = true;
      }) # status bar
      # qogir-theme # gtk theme
      # qogir-icon-theme # gtk theme
      # tokyonight-gtk-theme
      # gtk-engine-murrine
      # gnome-themes-extra
      # sassc # gtk theme engine
      # elementary-xfce-icon-theme
      lxappearance
      libsForQt5.qtstyleplugins # gtk style for qt
      libsForQt5.qt5ct
      lxappearance
      ueberzugpp # view images in terminals without sixel support

      # guis
      # anydesk # simple remote desktop
      google-chrome
      nemo-with-extensions # file manager
      file-roller
      vscode
      # jetbrains.idea-community-bin
      android-studio
      # jetbrains-toolbox # to install fleet editor: https://github.com/NixOS/nixpkgs/issues/242322#issuecomment-2264995861
      # (jetbrains.plugins.addPlugins jetbrains.idea-community [
      #   # https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/jetbrains/plugins/plugins.json
      #   "github-copilot"
      # ])
      # code-cursor # ai code editor
      # windsurf # ai code editor
      # zed-editor # ai code editor
      dbeaver-bin
      inkscape # svg editor
      gcolor3
      screenkey # screencast tool to display key presses
      zoom-us # TODO
      vlc # video player
      mpv # video player
      neovide # neovim gui
      (symlinkJoin {
        name = "megasync";
        paths = [megasync];
        buildInputs = [makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/megasync \
            --set QT_QPA_PLATFORM "wayland;xcb"
        '';
      }) # cloud file storage and sync
      krusader # file manager with good directory comparison
      keepassxc # password manager
      libsecret.out # secret-tool to retrieve secrets from keepassxc
      signal-desktop
      telegram-desktop
      spotify
      psst # alternative spotify client
      gthumb
      libreoffice
      sublime-merge
      lmstudio # local llm models
      # scribus
      # nheko # matrix client
      kvirc # irc client
      zathura # minimal pdf viewer with vim bindings
      # Installed by programs.firefox so Home Manager can wrap it with policies.
      # librewolf # firefox privacy fork
      kazam
      bottles # wine environment
      lutris # wine
      umu-launcher # for lutris
      joplin-desktop # note taking
      scrcpy # android remote control
      # vdhcoapp # for video download helper browser extension
      # anytype # p2p note taking
      # gitbutler # Git client for simultaneous branches on top of your existing workflow
    ])
    ++ [
      # Repo-managed Rust helper: focused-window cwd for "new terminal here" keybindings.
      # Replaces home/bin/xcwd-home (bash) and works on both X11 (xdotool) and niri (niri msg).
      (pkgs.callPackage ./bin/xcwd-home/package.nix {})

      # Fly.io Sprites CLI (stateful sandboxes). Not in nixpkgs; upstream has no public
      # source repo, binaries hosted on Tigris bucket. Bump `version` + `hash` when needed:
      #   curl -fsSL https://sprites-binaries.t3.storage.dev/client/v<ver>/sprite-linux-amd64.tar.gz.sha256
      # Docs: https://docs.sprites.dev/cli/installation/
      (pkgs.stdenvNoCC.mkDerivation rec {
        pname = "sprite";
        version = "0.0.1-rc43";
        src = pkgs.fetchurl {
          url = "https://sprites-binaries.t3.storage.dev/client/v${version}/sprite-linux-amd64.tar.gz";
          hash = "sha256-wEClvx4Kv7WK4uMYwNJqvsvjyQsonI01xlCo3z7CuwQ=";
        };
        nativeBuildInputs = [pkgs.autoPatchelfHook];
        buildInputs = [pkgs.glibc];
        sourceRoot = ".";
        installPhase = ''
          runHook preInstall
          install -Dm755 sprite $out/bin/sprite
          runHook postInstall
        '';
        meta.platforms = ["x86_64-linux"];
      })
    ];

  xdg.desktopEntries.signal = {
    name = "Signal";
    exec = ''signal-desktop --password-store="gnome-libsecret" %U'';
    terminal = false;
    icon = "signal-desktop";
    comment = "Private messaging from your desktop";
    mimeType = ["x-scheme-handler/sgnl" "x-scheme-handler/signalcaptcha"];
    categories = ["Network" "InstantMessaging" "Chat"];
  };
}
