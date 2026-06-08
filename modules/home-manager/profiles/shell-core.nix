# Portabler, headless-tauglicher Home-Manager-Core. Wird sowohl von shared.nix
# (volle Desktop-Konfiguration) als auch standalone (homeConfigurations,
# Template-Host) importiert. Enthält nur desktop-unabhängige Module und
# Shell-Essentials. Default-Theme "dark"; kein stylix, keine GUI-Terminals.
#
# Strikt headless: desktop-bezogene Aliase/Envs (BROWSER, qrscan, feh,
# signal-desktop, chromium-no-plugins, tclip, online-wait) leben in
# profiles/desktop-shell.nix bzw. launchers.nix, damit dieses Profil keine
# Desktop-Pakete (firefox/zbar/espeak) ins Closure zieht.
{
  config,
  lib,
  pkgs,
  ...
}: let
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";
in {
  imports = [
    ../shell.nix
    ../dotfiles.nix
    ../git.nix
    ../yazi.nix
    ./packages-cli.nix
  ];

  # https://nix-community.github.io/home-manager/index.xhtml
  home.username = lib.mkDefault "felix";
  home.homeDirectory = lib.mkDefault "/home/felix";

  home.sessionPath = [
    # Keep personal scripts live-editable without requiring a Home Manager switch.
    "${repoDir}/home/bin"
    "$HOME/bin"
    "$HOME/.cargo/bin"
    "$HOME/.npm-packages/bin"
  ];

  # home.sessionCommand

  home.sessionVariables = {
    CLICOLOR_FORCE = 1; # ANSI colors should be enabled no matter what. (https://bixense.com/clicolors/)

    PAGER = "less --RAW-CONTROL-CHARS"; # less with colors

    # colorize less
    LESS = "--use-color --RAW-CONTROL-CHARS --incsearch --ignore-case --redraw-on-quit --mouse --wheel-lines=3";

    # QT_QPA_PLATFORMTHEME = "gtk2"; # let qt apps use gtk 2 themes
    # QT_AUTO_SCREEN_SCALE_FACTOR = 1; # honor screen DPI
  };

  programs.bat.enable = true;
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = {}; # don't generate direnv.toml and use the existing one instead
  };

  home.shell = {
    enableIonIntegration = true;
  };

  home.shellAliases = {
    # /home/felix.old-2024-03-01/.aliases
    # /home/felix.old-2024-03-01/.sh_aliases

    # incubator
    s = "${pkgs.ddgr}/bin/ddgr";
    vf = ''$EDITOR "$HOME"/projects/dotfiles/flake.nix'';
    vt = ''$EDITOR "$HOME"/MEGAsync/notes/todo.md'';
    lg = "lazygit";
    nrb = "sudo nixos-rebuild boot";
    t1a = "exa --tree --color=always -L 1 -a";
    t2a = "exa --tree --color=always -L 2 -a";
    t3a = "exa --tree --color=always -L 3 -a";
    cat = "bat -n --paging=never";
    cd = "z";
    # rm = "${pkgs.trashy}/bin/trash put";
    sec = "source ${repoDir}/home/bin/secret-envs";
    # aider = "sec && ${pkgs.aider-chat}/bin/aider --no-check-update";
    alors = "sec && alors";
    opencode = "sec && opencode";
    oc = "sec && opencode";
    c = "sec && opencode --agent 'chat' ";
    ssh = "sec && TERM=xterm-256color ssh"; # fix colors in some ssh connections
    scp = "sec && scp";
    rg = "rg --hidden  --no-follow --no-heading --glob '!.git/*' --smart-case"; # https://github.com/BurntSushi/ripgrep/issues/623

    qr = "${pkgs.qrencode}/bin/qrencode -t ansiutf8";
    tw = "${pkgs.timewarrior}/bin/timew";

    ##################
    # well established
    dc = "docker-compose";

    vim = "nvim";

    v = ''nvim -c "FzfLua files"'';
    vg = ''nvim -c "FzfLua live_grep"'';
    vr = ''nvim -c "FzfLua oldfiles"''; # recently used files
    p = "cd $(select-project)";

    ls = "${pkgs.eza}/bin/eza --all --group-directories-first";
    l = "${pkgs.eza}/bin/eza -l";
    la = "${pkgs.eza}/bin/eza -la";
    lt = "${pkgs.eza}/bin/eza -l --sort newest";
    lta = "${pkgs.eza}/bin/eza -la --sort newest";
    t = "${pkgs.eza}/bin/eza --tree --color=always";
    ta = "${pkgs.eza}/bin/eza --tree --color=always -a";
    t1 = "${pkgs.eza}/bin/eza --tree --color=always -L 1";
    t2 = "${pkgs.eza}/bin/eza --tree --color=always -L 2";
    t3 = "${pkgs.eza}/bin/eza --tree --color=always -L 3";
    tg = "tree-git";
    vv = ''$EDITOR "$HOME"/projects/dotfiles/modules/home-manager/nvf.nix'';
    vn = ''$EDITOR "$HOME"/projects/dotfiles/hosts/gurke/default.nix'';
    vh = ''$EDITOR "$HOME"/projects/dotfiles/hosts/gurke/home.nix'';
    vp = ''$EDITOR "$HOME"/projects/dotfiles/modules/home-manager/packages.nix'';
    vb = ''$EDITOR "$HOME"/.config/polybar/config.ini'';
    nrs = "nrs";
    ns = "nix-shell --run zsh";
    ni = "nix profile install nixpkgs#";
    md = "mkdir -p";
    cdd = "cd ~/downloads";
    cdp = "cd ~/projects";
    rcp = "rsync --archive --partial --info=progress2 --human-readable";
    sys = "sudo systemctl";
    sysu = "systemctl --user";
    w = "watch --color --differences "; # trailing space is for alias expansion: https://unix.stackexchange.com/a/25329

    lsblk = "lsblk -o NAME,RM,SIZE,FSTYPE,LABEL,MOUNTPOINT,RO,UUID";

    ".." = "cd ..";
    cdt = "cd-tmp";

    m = "make";
    # mc = "make clean";
    drs = "$HOME/projects/ubunix/ubunix.sh";

    online = "ping -c 1 8.8.8.8 -W 5 && ping -c 1 google.com -W 5"; # -c <retries>  -W <timout>
    # alias on="w --interval=1 '$ONLINECMD'"
  };

  programs.ion = {
    # currently missing: I-Beam cursor in insert mode
    enable = true;
    shellAliases = config.home.shellAliases;
    initExtra = ''
      keybindings vi
    '';
  };

  # programs.command-not-found.enable = true;
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.nix-index-database.comma.enable = true;

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.ripgrep = {
    enable = true;
  };
  programs.eza = {
    # colorful ls alternative
    enable = true;
    git = true;
    icons = "auto";
  };

  services.ssh-agent.enable = true;

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "26.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
