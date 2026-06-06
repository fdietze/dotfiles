{pkgs, ...}: {
  home.packages =
    (with pkgs; [
      # shell / TUI essentials
      tmux
      zellij
      wget
      curl
      htop
      atop
      btop
      ncdu
      gdu
      duf
      pv
      bat
      lazygit
      tig
      git-fire
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
      inotify-tools
      lsof
      psmisc
      file
      smem
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
      trashy
      neovim-remote # used by nvim theme switcher
      bubblewrap
      nono
      pgcli
      sqlite-interactive
      timewarrior
      speedtest-cli
      nethogs
      # neovim editing stack
      clang # cc for nvim treesitter
      tree-sitter
      sccache
      rust-script
      python3
      nodejs
      opencode
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
    ])
    ++ [
      # context-mode MCP plugin (not in nixpkgs). Bump version+hash:
      #   nix-prefetch-url https://registry.npmjs.org/context-mode/-/context-mode-<ver>.tgz --type sha512
      (pkgs.callPackage ../bin/context-mode.nix {})

      # Wrap `claude` in the nono sandbox so it can't touch the rest of the system.
      # `nice -n 19` + `ionice -c 3` keep claude from starving interactive work of
      # CPU/IO when it spawns heavy subprocesses (builds, ripgrep over the tree).
      (pkgs.writeShellScriptBin "claude" ''
        export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
        exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 \
          ${pkgs.nono}/bin/nono run --profile claude -- \
          ${pkgs.claude-code}/bin/claude --dangerously-skip-permissions "$@"
      '')

      # Escape hatch: stock Claude on the host, with its own sandbox + permission prompts intact.
      (pkgs.writeShellScriptBin "vanilla-claude" ''
        export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
        exec ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 \
          ${pkgs.claude-code}/bin/claude "$@"
      '')
    ];
}
