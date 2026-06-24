{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs;
    [
    # shell / TUI essentials
    tmux
    screen
    zellij
    wget
    curl
    gnugrep
    gnused
    # awk: a POSIX shell essential. Pulled in transitively on full NixOS hosts,
    # but standalone shell-core targets (e.g. nix-on-droid korken) lack it, so
    # fzf's Ctrl-R history widget and shell.nix's worktree helpers break with
    # "awk not found". Provide it explicitly here.
    gawk
    htop
    btop
    ncdu
    gdu
    duf
    pv
    bat
    lazygit
    tig
    git-fire
    diff-so-fancy # git pager configured in home/files/.gitconfig. TODO: replace with delta
    nvd # diff nix generations/closures (used to verify rebuilds)
    dasel
    jq
    fd
    tldr
    gh
    tmate
    upterm
    entr
    socat
    ripgrep-all
    ouch
    atool
    p7zip
    zip
    unzip
    unrar
    tree
    moreutils
    netcat
    nmap
    calc
    lsof
    file
    dnsutils
    kondo
    yt-dlp
    flyctl
    miniserve
    gnumake
    gnupg
    openssl
    man
    exiftool
    qrencode
    neovim-remote # used by nvim theme switcher
    nono
    pgcli
    sqlite-interactive
    timewarrior
    speedtest-cli
    devbox # install dev tools in project; zshrc ruft `devbox global shellenv` (shell.nix)
    # neovim editing stack
    clang # cc for nvim treesitter
    tree-sitter
    sccache
    rust-script
    python3
    nodejs
    # language servers / formatters / linters
    nixd
    lua-language-server
    luarocks
    stylua
    lua
    nil
    nixfmt
    statix
    gopls
    gofumpt
    gomodifytags
    impl
    delve
    tailwindcss-language-server
    taplo
    docker-ls
    kotlin
    kotlin-language-server
    ktlint
    ruff
    pyright
    hadolint
    vtsls
    vscode-langservers-extracted
    bash-language-server
    shellcheck
    shfmt
    marksman
    markdownlint-cli2
    rtk
    ]
    # Kernel-/proc-/Landlock-gebundene Tools: bauen nicht (oder sinnlos) auf
    # Darwin. Per isLinux ausgeklammert, damit shell-core auf dem Mac baut.
    ++ lib.optionals pkgs.stdenv.isLinux [
      procps
      iproute2
      atop
      smem
      inotify-tools
      psmisc
      nethogs
      bubblewrap
      trashy
    ];
}
