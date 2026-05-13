{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # command line fu
    # https://github.com/ibraheemdev/modern-unix
    tmux
    wget # download files
    htop # fancy top
    ncdu # disk space analyzer
    gdu # disk space analyzer
    pv # shell progress bar
    pistol # file preview
    bat # cat with syntax highlighting
    lazygit # git tui
    tig # git tui
    dasel # transform data from csv/json/... (used by theme switcher)
    jq # json parser
    feh # image viewer
    neovim-remote # send commands to neovim instances (used by theme switcher)
    trashy # put files in trash instead of deleting them
    playerctl # control media players, like spotify, vlc via cli / keybindings
    pamixer # control pulseaudio via cli / keybindings
    fd # find files by filename, alternative to `find`
    tldr # quick command examples
    speedtest-cli
    gh # github cli
    autorandr # automatic monitor profiles
    xsel # clipboard
    xclip # clipboard
    tmate # invite someone else into your terminal via ssh
    upterm # tmate alternative
    imagemagick
    ffmpeg-full
    mediainfo
    entr # run commands when files change
    xcolor # simple color picker
    qrencode
    duf # better df
    socat
    ripgrep-all # ripgrep, but for documents
    ngrok # remote http tunnel
    chafa # preview images
    dragon-drop # file drag and drop initiated from command line
    pandoc # convert document formats
    texliveSmall # required by pandoc
    diff-so-fancy # diff viewer. TODO: replace with delta
    kondo # clear project files
    ouch # file compression
    btop # system monitor
    # curl-impersonate # curl mocking a real browser
    espeak # text to speech
    whisper-cpp # audio transcription
    alsa-utils # audo recording
    timewarrior # time tracking
    nrfconnect # bluetooth ble
    typst # modern latex alternative
    pulsemixer # audio mixer tui
    bluetuith # bluetooth tui
    nethogs # network traffic monitor per process
    yt-dlp # download youtube videos
    flyctl # fly.io command line tool

    networkmanagerapplet
    xcwd # returns current directory of x application, used to spawn new termanals in the current directory: ~/bin/xcwd-home
    arandr # manage monitors
    bubblewrap # sandboxing tool

    # system tools
    openssl
    man
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
    psmisc
    wirelesstools
    xbacklight
    acpi
    samba
    cifs-utils
    # mtpfs
    jmtpfs
    file
    smem
    dnsutils
    smartmontools # hard drive diagnostics

    # defaults
    lsof
    wget
    curl
    htop
    atop
    git-fire
    moreutils # vipe, sponge
    netcat
    nmap
    calc
    tree
    inotify-tools
    zip
    unzip
    unrar
    pavucontrol
    mimeo
    xdotool
    gnumake
    macchanger
    miniserve
    atool # archiver
    p7zip # compressor
    gnupg # cryptographic signing
    ghostscript # pdf (nvim)
    mermaid-cli # mermaid diagrams
    # development
    rust-script
    python3
    nodejs
    pgcli
    # earthly # better Dockerfiles
    devbox # install dev tools in project
    sqlite-interactive
    visualvm # jvm profiling
    clang # c-compiler, cc is required for nvim treesitter
    coursier # scala package manager, used to install metals
    # helix # modal editor
    sccache # compile cache
    devenv # nix based dev environments
    # code-cursor # ai code editor
    # antigravity-fhs # ai code editor from google
    opencode # ai coding agent
    # cursor-cli # ai coding agent
    tree-sitter # syntax highlighting toolkit (used by nvim)
    meld # git conflict resolution ui

    # language servers/formatters/linters
    nixd # nix language server
    lua-language-server
    luarocks
    stylua
    lua
    # alejandra # nix code formatter
    nil # nix language server
    nixfmt
    statix # nix linter
    # go language server
    gopls
    # gotools
    gofumpt
    gomodifytags
    impl
    delve
    # vtsls # TODO
    tailwindcss-language-server
    # nodePackages.prettier # css/js formatter
    taplo # toml language server
    docker-ls
    # llm-ls
    kotlin
    kotlin-language-server
    ktlint
    ruff # python
    pyright
    # codeium # ai completion
    hadolint # docker lint
    vtsls # typescript
    vscode-langservers-extracted

    bash-language-server
    shellcheck # shell language server
    shfmt
    marksman # markdown language server
    markdownlint-cli2

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
    elementary-xfce-icon-theme
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
    # goose-cli # cli ai agent
    # geminicommit
    dbeaver-bin
    # inkscape # svg editor, disabled because it is building from scratch because of stylix?
    gcolor3
    screenkey # screencast tool to display key presses
    zoom-us # TODO
    vlc # video player
    mpv # video player
    neovide # neovim gui
    megasync # cloud file storage and sync
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
    # vdhcoapp # for video download helper browser extension
    # anytype # p2p note taking
    # gitbutler # Git client for simultaneous branches on top of your existing workflow

  ];
}
