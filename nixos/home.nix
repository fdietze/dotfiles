# https://mipmip.github.io/home-manager-option-search/
{
  config,
  pkgs,
  ...
}: {
  # https://nix-community.github.io/home-manager/index.xhtml
  home.username = "felix";
  home.homeDirectory = "/home/felix";

  home.sessionPath = [
    "$HOME/bin"
  ];

  # home.sessionCommand 

  home.sessionVariables = {
    NIX_AUTO_INSTALL = "true";
    NIX_AUTO_RUN = "true";
    CLICOLOR_FORCE = 1; # ANSI colors should be enabled no matter what. (https://bixense.com/clicolors/)

    EDITOR = "nvim";
    BROWSER = "firefox";
    PAGER="less --RAW-CONTROL-CHARS"; # less with colors

    # colorize less
    LESS="--use-color --RAW-CONTROL-CHARS --incsearch --ignore-case --redraw-on-quit --mouse --wheel-lines=3";

    MOZ_USE_XINPUT2=1; # fix firefox scrolling, enable touchpad gestures
    LAUNCHER = "rofi -show drun";

    QT_QPA_PLATFORMTHEME="gtk2"; # let qt apps use gtk 2 themes
    QT_AUTO_SCREEN_SCALE_FACTOR=1; # honor screen DPI
  };

  home.activation.reloadHerbstluftwm = config.lib.dag.entryBetween ["reloadSystemD"] ["onFilesChange"] ''
    echo reloading herbstluftwm
    ${pkgs.herbstluftwm}/bin/herbstclient reload
  '';

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = ["firefox.desktop"];
      "x-scheme-handler/https" = ["firefox.desktop"];
      "x-scheme-handler/about" = ["firefox.desktop"];
      "x-scheme-handler/unknown" = ["firefox.desktop"];
    };
  };

  programs.bash.enable = true;
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autosuggestion.enable = true;
    defaultKeymap = "viins"; # vi mode
    history = rec {
      size = 100000000;
      save = size;
      extended = true; # save timestamps
    };

    shellGlobalAliases = {
      G = "| rg";
      H = "| head";
      L = "| less";
      C = "| xclip -selection clipboard";
      N="\"\$(\ls -tp | grep -v '\/$' | head -1)\"";
    };

    initExtra = ''
      # old:
      # https://github.com/dottr/dottr/tree/master/yolk/zsh
      # /home/felix.old-2024-03-01/wooofooozsh/.zshrc.old
      # https://github.com/fdietze/dotfiles/blob/master/.zshrc.vimode


      setopt nonomatch # avoid the zsh "no matches found" / allows typing sbt ~compile
      setopt interactivecomments # allow comments in interactive shell
      setopt hash_list_all # rehash command path and completions on completion attempt
      setopt BANG_HIST                 # Treat the '!' character specially during expansion.
      setopt INC_APPEND_HISTORY        # Write to the history file immediately, not when the shell exits.
      setopt SHARE_HISTORY             # Share history between all sessions.
      setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicate entries first when trimming history.
      setopt HIST_IGNORE_DUPS          # Don't record an entry that was just recorded again.
      setopt HIST_FIND_NO_DUPS         # Do not display a line previously found.
      setopt HIST_IGNORE_SPACE         # Don't record an entry starting with a space.
      setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks before recording entry.
      setopt HIST_VERIFY               # Don't execute immediately upon history expansion.


      # history prefix search
      autoload -U history-search-end # have the cursor placed at the end of the line once you have selected your desired command
      bindkey '^[[A' history-beginning-search-backward
      bindkey '^[[B' history-beginning-search-forward

      # zsh with pwd in window title
      function precmd {
          term=$(echo $TERM | grep -Eo '^[^-]+')
          print -Pn "\e]0;$term - zsh %~\a"
      }

      # current command with args in window title
      function preexec {
          term=$(echo $TERM | grep -Eo '^[^-]+')
          printf "\033]0;%s - %s\a" "$term" "$1"
      }

      # edit command line in vim
      autoload -z edit-command-line
      zle -N edit-command-line
      bindkey -M vicmd "^v" edit-command-line
      bindkey -M viins "^v" edit-command-line


      # beam cursor in vi insert mode
      # https://www.reddit.com/r/vim/comments/mxhcl4/setting_cursor_indicator_for_zshvi_mode_in/
      function zle-keymap-select () {
        case $KEYMAP in
          vicmd) echo -ne '\e[1 q';; # block
          viins|main) echo -ne '\e[5 q';; # beam
          esac
      }
      zle -N zle-keymap-select
        zle-line-init() {
          zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
            echo -ne "\e[5 q"
        }
      zle -N zle-line-init
      echo -ne '\e[5 q' # Use beam shape cursor on startup.
      preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.


      # map HOME/END in vi mode
      # https://github.com/jeffreytse/zsh-vi-mode/issues/59#issuecomment-862729015
      # https://github.com/jeffreytse/zsh-vi-mode/issues/134
      bindkey -M viins "^[[H" beginning-of-line
      bindkey -M viins  "^[[F" end-of-line
      bindkey -M vicmd "^[[H" beginning-of-line
      bindkey -M vicmd "^[[F" end-of-line
      bindkey -M visual "^[[H" beginning-of-line
      bindkey -M visual "^[[F" end-of-line





      export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
      export FZF_DEFAULT_OPTS="--extended --multi --ansi --exit-0" # extended match and multiple selections
      export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
      export FZF_CTRL_T_OPTS="--tac --height 90% --reverse --preview 'pistol {} \$FZF_PREVIEW_COLUMNS \$FZF_PREVIEW_LINES' --bind 'ctrl-d:preview-page-down,ctrl-r:reload($FZF_CTRL_T_COMMAND)"


      insertCommitHash () {
        commits=$(~/bin/git-select-commit)
        [[ -z "$commits" ]] && zle reset-prompt && return 0
        LBUFFER+="$commits"
        local ret=$?
        zle reset-prompt
        return $ret
      }
      zle -N insertCommitHash
      bindkey '^g' insertCommitHash



      # colorize manpages
      LESS_TERMCAP_mb="$(tput bold; tput setaf 6)";
      LESS_TERMCAP_md="$(tput bold; tput setaf 2)";
      LESS_TERMCAP_me="$(tput sgr0)";
      LESS_TERMCAP_so="$(tput bold; tput setaf 0; tput setab 6)";
      LESS_TERMCAP_se="$(tput rmso; tput sgr0)";
      LESS_TERMCAP_us="$(tput smul; tput bold; tput setaf 3)";
      LESS_TERMCAP_ue="$(tput rmul; tput sgr0)";
      LESS_TERMCAP_mr="$(tput rev)";
      LESS_TERMCAP_mh="$(tput dim)";
      LESS_TERMCAP_ZN="$(tput ssubm)";
      LESS_TERMCAP_ZV="$(tput rsubm)";
      LESS_TERMCAP_ZO="$(tput ssupm)";
      LESS_TERMCAP_ZW="$(tput rsupm)";
      GROFF_NO_SGR=1;

      # TODO: fzf for $(git-select-dirty-files)

# x() { # open a gui command and close the terminal
#     zsh -i -c "$@ &; disown" 
#     exit
# }


# sshforward() {
#     # usage: sshforward host remoteport [localport]
#     REMOTEHOST=$1
#     REMOTELOCALPORT=$2
#     LOCALPORT=$${3:-$2}
#     shift 3
#     ssh -NL $${LOCALPORT}:localhost:$${REMOTELOCALPORT} $${REMOTEHOST} $@
# }
    '';

    plugins = [
      {
        name = "zsh-system-clipboard";
        src = pkgs.zsh-system-clipboard;
        file = "share/zsh/zsh-system-clipboard/zsh-system-clipboard.zsh";
      }
      {
        name = "zsh-print-alias";
        file = "print-alias.plugin.zsh";
        src = pkgs.fetchFromGitHub {
          owner = "brymck";
          repo = "print-alias";
          rev = "8997efc356c829f21db271424fbc8986a7203119";
          sha256 = "sha256-6ZyRkg4eXh1JVtYRHTfxJ8ctdOLw4Ff8NsEqfpoxyfI=";
        };
      }
    ];
  };
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.starship = {
    # https://starship.rs/config/
    enable = true;
    enableZshIntegration = true;
    settings = {
      git_status.stashed = ""; # disable stash indicator
      python.disabled = true;
      rust.disabled = true;
      scala.disabled = true;
      java.disabled = true;
      docker_context.disabled = true;
      dart.disabled = true;
      package.disabled = true; # do not show npm, cargo etc
      nodejs.disabled = true;
    };
  };

  programs.bat.enable = true;
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = {}; # don't generate direnv.toml und use the existing one instead
  };

  home.shellAliases = {
    # /home/felix.old-2024-03-01/.aliases
    # /home/felix.old-2024-03-01/.sh_aliases

    # incubator
    s = "${pkgs.ddgr}/bin/ddgr";
    vf = "\$EDITOR \"$HOME\"/nixos/flake.nix";
    vt = "\$EDITOR \"$HOME\"/todo.md";
    lg = "lazygit";
    nrb = "sudo nixos-rebuild boot";
    t2a = "exa --tree --color=always -L 2 -a";
    t3a = "exa --tree --color=always -L 3 -a";
    n = "yazi";
    # cat = "bat -n --paging=never";
    cd = "z";
    rm = "trash-put";
    sec = "source $HOME/bin/secret-envs";
    aider-docker = "sec && docker run -it --volume $(pwd):/app --user $(id -u):$(id -g) paulgauthier/aider --openai-api-key $OPENAI_API_KEY --4turbo";
    db = "devbox";
    dbs = "devbox shell";
    dbre = "refresh"; # devbox: refresh shell
    c = "sec && aichat";
    # cb = "sec && $HOME/bin/cb";
    cb = "sec && aichat -e";
    cq = "sec && $HOME/bin/cq";
    e = "earthly";
    ssh="TERM=xterm-256color ssh"; # fix colors in some ssh connections
    rg="rg --hidden  --no-follow --no-heading --glob '!.git/*' --smart-case"; # https://github.com/BurntSushi/ripgrep/issues/623

    qrscan="LD_PRELOAD=/usr/lib/libv4l/v4l1compat.so zbarcam --raw /dev/video0";
    tclip="tmate display -p \"#{tmate_ssh}\" | xclip -selection clipboard";  # tmate session token to clipboard
    tw="timew";
    tf="terraform";
 

    ##################
    # well established
    dc = "docker-compose";

    vim = "\$EDITOR";

    v = "nvim -c \"Telescope find_files\"";
    vg = "nvim -c \"Telescope live_grep\"";
    vr = "nvim -c \"Telescope oldfiles\""; # recently used files
    vp = "nvim -c \"Telescope projects\"";
    p = "cd \$(select-project)";


    # git
    g = "git";
    gs = "git status";
    gb = "git branch";
    gu = "sec && git up";
    gp = "sec && git p";
    gpf = "sec && git pf";
    gl = "git lg";
    gla = "git lga";
    gdf = "git df --no-index";
    tig = "tig status";

    ls = "eza --all --group-directories-first";
    l = "ls -l";
    la = "ls -la";
    lt = "ls -l --sort newest";
    lta = "ls -la --sort newest";
    t = "eza --tree --color=always";
    ta = "eza --tree --color=always -a";
    t2 = "eza --tree --color=always -L 2";
    t3 = "eza --tree --color=always -L 3";
    tg = "tree-git";
    vv = "\$EDITOR ~/.config/nvim/init.lua";
    vn = "\$EDITOR \"$HOME\"/nixos/configuration.nix";
    vh = "\$EDITOR \"$HOME\"/nixos/home.nix";
    vb = "\$EDITOR \"$HOME\"/.config/polybar/config.ini";
    nrs = "sudo nixos-rebuild switch";
    ns = "nix-shell --run zsh";
    ni = "nix profile install nixpkgs#";
    md = "mkdir -p";
    cdd = "cd ~/downloads";
    cdp = "cd ~/projects";
    rcp = "rsync --archive --partial --info=progress2 --human-readable";
    sys = "systemctl";
    sysu = "systemctl --user";
    watch="watch -c -d";
    w="watch -c -d bash -i -c";
    chromium="chromium --force-device-scale-factor=1.5"; # fix highdpi for chromium
    chromium-no-plugins="chromium --disable-extensions --disable-plugins";



    lsblk="lsblk -o NAME,RM,SIZE,FSTYPE,LABEL,MOUNTPOINT,RO,UUID";

    ".." = "cd ..";
    hc = "herbstclient";
    cdt = "cd-tmp";

   m="make";
   mc="make clean";
   drs="$HOME/projects/ubunix/ubunix.sh";


# # online checking tools
# ONLINECMD='ping -c 1 8.8.8.8 -W 5 && ping -c 1 google.com -W 5'
# alias online="$ONLINECMD" # -c <retries>  -W <timout>
# alias online-wait='until online; do; sleep 3; done; espeak -p 30 "online"; espeak -p 80 "online"; espeak -p 50 "online"'
# alias on="w --interval=1 '$ONLINECMD'"


  };

  # programs.command-not-found.enable = true;
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };

  xdg.userDirs = {
    download = "${config.home.homeDirectory}/downloads";
  };

  programs.neovim = {
    # ~/.config/nvim/init.lua
    enable = true;
    plugins = with pkgs.vimPlugins; [
      nvim-treesitter.withAllGrammars
    ];
  };

  # programs.atuin = {
  #   enable = true;
  #   enableZshIntegration = true;
  #   flags = [
  #     "--disable-up-arrow"
  #   ];
  #   settings = {
  #     # https://docs.atuin.sh/configuration/config/
  #     theme = "tokyo_night";
  #     style = "compact";
  #     enter_accept = true;
  #     inline_height = 10;
  #   };
  # };

  programs.git = {
    # enable = true;
    # userName = "Felix Dietze";
    # userEmail = "github@felx.me";
    difftastic = {
      enable = true;
    };
  };

  programs.alacritty.enable = true;
  # services.polybar = {
  #   enable = true;
  #   script = ''
  #     export PATH="/run/current-system/sw/bin:$PATH"
  #        source "$HOME/bin/theme-env"
  #        polybar &
  #   '';
  # };
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      return {
        color_scheme = "tokyonight_storm",
        -- color_scheme = "Catppuccin Latte",
        default_cursor_style = 'SteadyBar',
        cursor_blink_rate = 0,
        enable_tab_bar = false,
        font_size = 7.0,
        window_padding = {
          left = "2px",
          right = "2px",
          top = "2px",
          bottom = "2px",
        },
      }
    '';
  };
  services.copyq.enable = true;

  services.redshift = {
    # Redshift adjusts the color temperature of your screen. This may help your eyes hurt less if you are working in front of the screen at night.
    enable = true;
    provider = "geoclue2";
  };

  services.unclutter = {
    # hide mouse after some seconds of no movement
    enable = true;
  };

  services.playerctld.enable = true;

  services.blueman-applet.enable = true; # bluetooth tray icon, needs dconf
  services.mpris-proxy.enable = true; # bluetooth buttons

  services.dunst = {
    # https://github.com/dunst-project/dunst/blob/master/dunstrc
    # old configFile = "$HOME/.config/dunst/dunstrc.old";
    enable = true;
    settings = {
      global = {
        frame_width = 1;
        frame_color = "#9ECE6A";
        font = "Monospace 7";
      };
      urgency_normal = {
        background = "#191C26";
        foreground = "#eceff1";
      };
    };
  };

  services.flameshot = {
    enable = true;
    settings = {
      General = {
        checkForUpdates=false;
        contrastOpacity=51;
        disabledTrayIcon=true;
        drawColor="#00ffff";
        filenamePattern="%F_%H-%M-%S";
        savePath="/home/felix/screenshots";
        savePathFixed=true;
        showStartupLaunchMessage=false;
      };
    };
  };

  # todo: darkman
  xsession = {
    enable = true;
    windowManager.herbstluftwm = {
      enable = true;
      tags = ["1" "2" "3" "4" "5" "6" "7" "8" "9"];
      keybinds = rec {
        # launchers
        # if there is an alacritty window, spawn a new window.
        # Working directory is current directory of currently focused window.
        # Mod1-d = "spawn sh -c 'alacritty msg create-window --working-directory \"$($HOME/bin/xcwd-home)\" || alacritty --working-directory \"$($HOME/bin/xcwd-home)\"'";
        Mod1-d = "spawn sh -c 'alacritty --working-directory \"$($HOME/bin/xcwd-home)\"'";
        # Mod1-d = "spawn sh -c 'wezterm start --cwd \"$($HOME/bin/xcwd-home)\"'";
        Mod1-Shift-d = "chain , rule once class=Alacritty floating=on floatplacement=center , spawn alacritty -o font.size='14' -e sh -c 'source $HOME/bin/secret-envs && aichat'";
        Mod1-y = "spawn $LAUNCHER";
      Mod1-j = "spawn $BROWSER";
        # Mod1-´ = "spawn $BROWSER";
        Mod1-Apostrophe = "spawn $BROWSER";
        Mod1-period = "spawn ${pkgs.neovide}/bin/neovide $HOME/todo.md";

        Mod1-q = "close_and_remove";
        Mod1-x = "close_and_remove";
        Mod1-k = "spawn xkill";

        # focusing clients (iale are positions of neo layout arrow keys)
        Mod1-Left = "focus left";
        Mod1-Down = "focus down";
        Mod1-Up = "focus up";
        Mod1-Right = "focus right";
        Mod1-i = "focus left";
        Mod1-a = "focus down";
        Mod1-l = "focus up";
        Mod1-e = "focus right";
        Mod1-Tab = "cycle_all";

        # moving clients
        Mod1-Shift-Left = "shift left";
        Mod1-Shift-Down = "shift down";
        Mod1-Shift-Up = "shift up";
        Mod1-Shift-Right = "shift right";
        Mod1-Shift-i = "shift left";
        Mod1-Shift-a = "shift down";
        Mod1-Shift-l = "shift up";
        Mod1-Shift-e = "shift right";

        # cycle through tags
        Mod1-c = "use_index +1 --skip-visible";
        Mod1-Shift-c = "chain , move_index +1 --skip-visible , use_index +1 --skip-visible";
        Mod1-Shift-Ctrl-c = "move_index +1 --skip-visible";
        Mod1-v = "use_index -1 --skip-visible";
        Mod1-Shift-v = "chain , move_index -1 --skip-visible , use_index -1 --skip-visible";
        Mod1-Shift-Ctrl-v = "move_index -1 --skip-visible";
        Mod1-w = "use_previous";
        Mod1-Shift-w = "spawn $HOME/bin/hc-move-previous";

        # splitting frames
        # create an empty frame at the specified direction ( .62 is golden ratio)
        Mod1-g = "chain , split top 0.38 , focus up";
        Mod1-r = "chain , split bottom 0.62 , focus down";
        Mod1-n = "chain , split left 0.38 , focus left";
        Mod1-t = "chain , split right 0.62 , focus right";

        # resizing frames
        Mod1-Shift-g = "resize up +0.02";
        Mod1-Shift-r = "resize down +0.02";
        Mod1-Shift-n = "resize left +0.02";
        Mod1-Shift-t = "resize right +0.02";

        # layouting
        # let the current frame explode into subframes
        Mod1-m = "split explode";
        Mod1-Shift-m = "split explode";
        # collapse the current frame
        Mod1-comma = "remove";
        Mod1-Shift-comma = "remove";
        Mod1-Shift-h = "cycle_layout 1 grid horizontal vertical";
        Mod1-f = "fullscreen toggle";
        Mod1-h = "set_attr clients.focus.floating toggle";

        # focus monitors
        Mod1-o = "focus_monitor +1";
        Mod1-u = "focus_monitor -1";
        Mod1-Shift-o = "chain , shift_to_monitor +1 , focus_monitor +1";
        Mod1-Shift-u = "chain , shift_to_monitor -1 , focus_monitor -1";
        Mod1-Shift-Ctrl-o = "shift_to_monitor +1";
        Mod1-Shift-Ctrl-u = "shift_to_monitor -1";
        Mod1-F7 = "spawn autorandr --change"; # detect connected monitors, apply right profile

        # window manager & system
        Mod1-Shift-q = "quit";
        Mod1-Shift-x = "quit";
        Mod1-Shift-y = "reload";
        Mod1-Ctrl-Shift-q = "spawn poweroff";
        Mod1-Ctrl-Shift-x = "spawn poweroff";
        Mod1-Ctrl-Shift-y = "spawn reboot";
        # lock screen
        Mod1-Escape = "spawn bash -c '$HOME/bin/lock'";

        #   # switch color scheme
        Mod1-Ctrl-k = "spawn bash -c '$HOME/bin/theme light > /dev/null 2>&1'";
        Mod1-Ctrl-s = "spawn bash -c '$HOME/bin/theme dark > /dev/null 2>&1'";

        # media keys
        XF86KbdBrightnessDown = "spawn keyboardbacklightoff";
        XF86KbdBrightnessUp = "spawn keyboardbacklightmax";
        XF86MonBrightnessDown = "spawn light -U 5";
        XF86MonBrightnessUp = "spawn light -A 5";
        XF86TouchpadToggle = "spawn touchpadtoggle";
        XF86AudioRaiseVolume = "spawn pamixer --increase 5";
        XF86AudioLowerVolume = "spawn pamixer --decrease 5";
        XF86AudioMute = "spawn pamixer -t";
        # bluetooth
        XF86Bluetooth = "spawn bluetoothtoggle";

        # adjust volume
        Mod1-Ctrl-h = "spawn pamixer --increase 5";
        Mod1-Ctrl-n = "spawn pamixer --decrease 5";
        Mod1-Ctrl-m = "spawn pamixer -t";

        # adjust screen brightness
        Mod1-Ctrl-g = "spawn light -A 5";
        Mod1-Ctrl-r = "spawn light -U 5";
        Mod1-Ctrl-Shift-g = "spawn light -A 1";
        Mod1-Ctrl-Shift-r = "spawn light -U 1";

        #   # control media players with yxcvb (üöäpz on NEO)
        Mod1-udiaeresis = "spawn playerctl previous";
        Mod1-odiaeresis = "spawn playerctl play";
        Mod1-adiaeresis = "spawn playerctl play-pause";
        Mod1-p = "spawn playerctl stop";
        Mod1-z = "spawn playerctl next";

        # Screenshots
        Print = "spawn ${pkgs.scrot}/bin/scrot 'screenshots/%Y-%m-%d_%H-%M-%S.png' --exec '${pkgs.libnotify}/bin/notify-send --expire-time=2000 \"Fullscreen Screenshot Saved.\"'";
        Ctrl-Mod1-Print = "spawn ${pkgs.flameshot}/bin/flameshot gui"; # TODO: ctrl-c to copy image does not work. because flameshot is not running in the background?
        
        # incubator
        # Mod1- = "keepmenu ~/";

        # wallpapers
      #   hc keybind ''$Mod-Ctrl-Shift-n spawn ''$HOME/bin/frottage
        Mod1-Ctrl-Shift-s = "spawn $HOME/bin/frottage-save";
      #   hc keybind ''$Mod-Ctrl-Shift-s spawn ''$HOME/bin/frottage-save
      #   # hc keybind ''$Mod-Ctrl-Shift-Right spawn ''$HOME/projects/wpfr/seek 0.5
      #   # hc keybind ''$Mod-Ctrl-Shift-Left spawn ''$HOME/projects/wpfr/seek -0.5
      #   # hc keybind ''$Mod-Ctrl-Shift-m spawn ''$HOME/projects/wpfr/play
      #   # hc keybind ''$Mod-Ctrl-Shift-comma spawn ''$HOME/projects/wpfr/stop
      };

      mousebinds = {
        # mouse
        Mod1-B1 = "move"; # click + drag
        Mod1-B3 = "resize"; # right click + drag
        Mod4-B1 = "resize"; # easier resize for touchpads
        Mod1-B2 = "zoom"; # middle click: resize in all directions
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
        smart_window_surroundings = true; # hides tabs?
        smart_frame_surroundings = true; # hides tabs?
        focus_stealing_prevention = 0; # zoom problems
        # tabs
        tabbed_max = true;
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
        "class=\"Signal\" tag=1"
        "class=\"VirtualBox Manager\" tag=6"
        "class=\"KeePassXC\" tag=8"
        "class=\"KeePassXC\" windowtype='_NET_WM_WINDOW_TYPE_DIALOG' focus=on switchtag=on" # keepass dialogs
        "class=\"Spotify\" tag=9"

        # zoom
        "class='zoom' title='zoom' floating=on tag=9" # notifications, sometimes detects the app window
        "class='zoom' title='Zoom Cloud Meetings' floating=on" # launch and closing screen
        "title~'^Zoom - .*' floating=off" # zoom app
        "class='zoom' title='Zoom' floating=off" # connecting to meeting...
        "title='Zoom Meeting' floating=off" # zoom meeting
        "class='zoom' title='share_preview_window' floating=on hook=close-hook" # screen sharing preview popup
      ];

      extraConfig = ''
        # tags keybindings
        tag_names=({1..9})
        tag_keys=({1..9} 0)

        hc rename default "''${tag_names[0]}" || true
        for i in ''${!tag_names[@]}; do
        	hc add "''${tag_names[$i]}"
        	key="''${tag_keys[$i]}"
        	if ! [ -z "$key" ]; then
        		herbstclient keybind "Mod1-$key" use_index "$i"
        		herbstclient keybind "Mod1-Shift-$key" chain , move_index "$i" , use_index "$i"
        		herbstclient keybind "Mod1-Shift-Ctrl-$key" move_index "$i"
        	fi
        done

        source "$HOME/bin/theme-env" # gives different colors depending on "$HOME/.theme"
        herbstclient attr theme.tiling.reset 1
        herbstclient attr theme.floating.reset 1
        herbstclient set window_border_width 3
        herbstclient set frame_border_width 3
        herbstclient attr theme.floating.border_width 3
        herbstclient attr theme.title_when multiple_tabs # tabbed mode in 'max' layout

        herbstclient set frame_border_active_color $WM_BORDER_FOCUSED
        herbstclient set frame_border_normal_color $WM_BORDER_NORMAL
        herbstclient set window_border_active_color $WM_BORDER_FOCUSED
        herbstclient set window_border_normal_color $WM_BORDER_NORMAL
        herbstclient attr theme.urgent.color orange

        frottage & # set wallpaper

        xsetroot -cursor_name left_ptr # apply cursor theme globally


        (
        pkill polybar || true
        pkill -9 polybar || true

        rm -f /tmp/msgg
        set -e

        # show polybar tray on primary monitor
        # https://github.com/polybar/polybar/issues/1070


        HLWM_MONITOR_IDS=$(${pkgs.herbstluftwm}/bin/herbstclient list_monitors | cut -d':' -f1)
        # example line: 0
        echo "command $(${pkgs.herbstluftwm}/bin/herbstclient list_monitors)" >> /tmp/msgg
        echo HLWM_MONITOR_IDS: $HLWM_MONITOR_IDS >> /tmp/msgg

        POLYBAR_MONITOR_IDS_PRIMARY=$(polybar --list-monitors | awk -F: '{print $1 ($2~/primary/?" (primary)":"")}')
        # example line: eDP-1 (primary)
        echo POLYBAR_MONITOR_IDS_PRIMARY: $POLYBAR_MONITOR_IDS_PRIMARY >> /tmp/msgg

        MERGED=$(paste -d " " <(echo "$HLWM_MONITOR_IDS") <(echo "$POLYBAR_MONITOR_IDS_PRIMARY"))
        # example line: 0 eDP-1 (primary)
        echo MERGED: $MERGED >> /tmp/msgg

        PRIMARY=$(echo "$MERGED" | grep "primary" || true)
        OTHERS=$(echo "$MERGED" | grep -v "primary" || true)
        echo PRIMARY: $PRIMARY >> /tmp/msgg
        echo OTHERS: $OTHERS >> /tmp/msgg


        # first, launch polybar on primary monitor
        export MONITOR=$(echo "$PRIMARY" | cut -d" " -f2) # used in ~/.config/polybar/config.ini
        export MONITOR_HLWM=$(echo "$PRIMARY" | cut -d" " -f1) # passed via ~/.config/polybar/config.ini to ~/.config/herbstluftwm/tags.sh
        echo "Starting polybar on primary monitor '$PRIMARY' $MONITOR_HLWM ($MONITOR)" >> /tmp/msgg
        ${pkgs.polybar}/bin/polybar &

        # after waiting a bit, launch polybar on other monitors
        sleep 2
        IFS=$'\n' # loop over whole lines
        echo "$OTHERS" | while read -r m; do
            # if line is empty, skip
            if [ -z "$m" ]; then
                continue
            fi
            export MONITOR=$(echo "$m" | cut -d" " -f2)
            export MONITOR_HLWM=$(echo "$m" | cut -d" " -f1)
            # Start polybar in the background and optionally manage PIDs
            echo "Starting polybar on other monitor '$m' $MONITOR_HLWM ($MONITOR)" >> /tmp/msgg
            ${pkgs.polybar}/bin/polybar &
        done
        ) > /tmp/polybar.log 2>&1



      '';

      # extraConfig = ''
      #
      #   # hc keybind ''$Mod-d spawn sh -c 'alacritty msg create-window --working-directory "''$(''$HOME/bin/xcwd-home)" -e bash -c "source ~/.zshenv; exec zsh" || alacritty --working-directory "''$(''$HOME/bin/xcwd-home)" -e bash -c "source ~/.zshenv; exec zsh"' # alias from .sh_aliases
      #   # hc keybind ''$Mod-d spawn sh -c 'wezterm start --cwd "''$(''$HOME/bin/xcwd-home)" -- bash -c "source ~/.zshenv; exec zsh"'
      #   # hc keybind ''$Mod-d spawn sh -c 'rio --working-dir "''$(''$HOME/bin/xcwd-home)" --command bash -c "source ~/.zshenv; exec zsh"'
      #   # hc keybind ''$Mod-d spawn sh -c 'termite --directory "''$(''$HOME/bin/xcwd-home)" --exec "bash -c \"source ~/.zshenv; exec zsh\""'
      #   hc keybind ''$Mod-d spawn sh -c 'alacritty --working-directory "''$(''$HOME/bin/xcwd-home)"'
      #
      #   hc keybind ''$Mod-0 spawn sh -c 'xprop >> ~/propslog'
      #
      #
      #
      #
      #
      #
      #
      #
      #
      #
      #
      # win-info() (
      # 	win_id=''$1
      #
      # 	echo -n "''$win_id "
      #
      # 	match_int='[0-9][0-9]*'
      # 	match_string='".*"'
      # 	match_qstring='"[^"\\]*(\\.[^"\\]*)*"' # NOTE: Adds 1 backreference
      #
      # 	{
      # 		# Run xprop, transform its output into i3 criteria. Handle fallback to
      # 		# WM_NAME when _NET_WM_NAME isn't set
      # 		xprop -id ''$win_id |
      # 			sed -nr \
      # 				-e "s/^WM_CLASS\(STRING\) = (''$match_qstring), (''$match_qstring)''$/instance=\1\nclass=\3/p" \
      # 				-e "s/^WM_WINDOW_ROLE\(STRING\) = (''$match_qstring)''$/window_role=\1/p" \
      # 				-e "/^WM_NAME\(STRING\) = (''$match_string)''$/{s//title=\1/; h}" \
      # 				-e "/^_NET_WM_NAME\(UTF8_STRING\) = (''$match_qstring)''$/{s//title=\1/; h}" \
      # 				-e ' ''${g; p}' # remove space before double single quotes, was added for nix escaping to work
      # 	} | sort | tr "\n" " " | sed -r 's/^(.*) ''$/[\1]\n/'
      # )
      #
      #
      # herbstclient -il rule info-hook | while read win_id; do
      # 	win-info ''$win_id >>/tmp/hc-hooks
      # done &
      #
      #
      #
      #
      #   # rules
      #
      #   # close hook
      #   # https://github.com/herbstluftwm/herbstluftwm/issues/1536#issuecomment-1331169428
      #   herbstclient -il rule close-hook | while read win_id; do
      #   	herbstclient close ''$win_id
      #   	echo "close-hook: ''$win_id" >>/tmp/hc-hooks
      #   done &
      #
      #
      #   # rules
      #   #hc rule class=XTerm tag=3 # move all xterms to tag 3
      #   hc rule focus=on # normally focus new clients
      #   hc rule floatplacement=smart
      #   #hc rule focus=off # normally do not focus new clients
      #   # give focus to most common terminals
      #   hc rule class~'(.*[Rr]xvt.*|.*[Tt]erm|Konsole|alacritty)' focus=on
      #
      #
      #
      #
      #
      #   # for_window [title="alacritty-fzf-run"] floating enable, resize set 800 px 800 px; move position center; exec --no-startup-id xdotool search --title alacritty-fzf-run behave %@ blur windowclose
      #   hc rule title='alacritty-fzf-run' floating=on floatplacement=center
      #   hc rule class='mpv' floating=on floatplacement=center floating_geometry=1280x1024
      #   hc rule class='vlc' floating=on floatplacement=center floating_geometry=1280x1024
      #
      #   # intellij file finder dialog xprop:
      #   # WM_CLASS(STRING) = "sun-awt-X11-XWindowPeer", "jetbrains-studio"
      #   # WM_CLIENT_LEADER(WINDOW): window id # 0x3200023
      #   # _NET_WM_NAME(UTF8_STRING) = "win25"
      #   # WM_NAME(STRING) = "win25"
      #
      #   # unlock, just to be sure
      #   hc unlock
      #
      #   herbstclient set tree_style '╾│ ├└╼─┐'
      #
      #
      #   # "''$HOME/bin/theme" >/tmp/theme_debug 2>&1 &
      #   # "''$HOME/bin/theme" >/dev/null 2>&1 &
      #
      #   # wait
      # '';
    };
    profileExtra = ''
      (

      function current_wifi {
      	${pkgs.networkmanager}/bin/nmcli -t -f active,ssid dev wifi | grep -E '^yes' | cut -d: -f2
      }

      # https://github.com/NixOS/nixpkgs/issues/119513
      if [ -z "$_XPROFILE_SOURCED" ]; then
        export _XPROFILE_SOURCED=1

        autorandr --change & # detect monitors
        (sleep 2 && keepassxc) &
        (
          set -e
          sleep 60
          # if current wifi is not empty and not "kronk" (mobile hotspot), start megasync
          CURRENT_WIFI=$(current_wifi)
          echo $CURRENT_WIFI > /tmp/current_wifi
          if [ -n "$CURRENT_WIFI" ] && [ "$CURRENT_WIFI" != "kronk" ]; then
            # QT_SCALE_FACTOR fixes megasync UI
            # QT_SCALE_FACTOR=1
            ${pkgs.megasync}/bin/megasync > /tmp/megasync_logs 2>&1 &
          fi
        ) &
      fi
      wait
      ) >/tmp/xsession_debug 2>&1 &
    '';
  };

  services.picom = {
    enable = true;
    vSync = true;
  };
  services.xsettingsd = {
    enable = true;
    settings = {
      # for dark-light theme switching, the config file needs to be mutable:
      # ~/.config/xsettingsd/xsettingsd.conf
      # It will be modified by the script ~/bin/theme
      #
      # # https://github.com/derat/xsettingsd/wiki/Settings
      #
      # "Xft/Hinting" = 1;
      # "Xft/HintStyle" = "hintslight";
      # "Xft/Antialias" = 1;
      # "Xft/RGBA" = "rgb";
      # "Net/ThemeName" = "Qogir-Dark";
      # "Net/IconThemeName" = "Qogir-dark";
    };
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

  # services.megasync.enable = true; # is started in ~/.xprofile

  # gtk = {
  #   enable = true;
  #   theme = {
  #     name = "Qogir-Dark";
  #     package = pkgs.qogir-theme;
  #   };
  #   iconTheme = {
  #     name = "Qogir-Dark";
  #     package = pkgs.qogir-icon-theme;
  #   };
  # };

  gtk.cursorTheme = {
    name = "Vanilla-DMZ";
    # size = 64;
  };

  home.pointerCursor = {
    x11.enable = true;
    gtk.enable = true;
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
  };

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
    icons = true;
  };
  services.network-manager-applet.enable = true;

  # programs.ssh = {
  #   enable = true;
  # };

  services.ssh-agent.enable = true;

  programs.rofi = {
    # application launcher, window switcher, ssh launcher
    enable = true;
    # font = "Droid Sans Mono 30";
    theme = builtins.fetchurl {
      url = "https://raw.githubusercontent.com/catppuccin/rofi/5350da41a11814f950c3354f090b90d4674a95ce/basic/.local/share/rofi/themes/catppuccin-macchiato.rasi";
      sha256 = "0n9cixyv4ladvcfbybq5dsfyzklfh732cd8nmvjckd09pjkb62f1";
    };
    font = "Commit Mono 18";

    plugins = with pkgs; [rofi-vpn rofi-calc rofi-emoji rofi-systemd rofi-bluetooth rofi-pulse-select rofi-file-browser];
  };
  programs.firefox.enable = true;
  programs.qutebrowser = {
    enable = true;
    loadAutoconfig = true;
    enableDefaultBindings = true;
    keyBindings = {
      normal = {
        "l" = "tab-next";
        "L" = "tab-prev";
        "ü" = "tab-close";
        "ä" = "close";
        "<Ctrl-f>" = "cmd-set-text /";
        "<Ctrl-t>" = "cmd-set-text --space :open -t";
        "<Ctrl-l>" = "command-accept";
        "<Ctrl-o>" = "back";
        "<Ctrl-i>" = "forward";
        "F12" = "devtools";
      };
    };
    extraConfig = ''
      config.source('config-theme.py')
    '';
  };
  programs.chromium.enable = true;
  programs.yazi = {
    # file manager
    enable = true;
    enableZshIntegration = true;
  };

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
      run-theme = ''$HOME/bin/theme'';
    };
  };

  home.packages = with pkgs; [
    # command line fu
    wget # download files
    htop # fancy top
    atop # process monitor with good highlight of resource bottlenecks
    ncdu # disk space analyzer
    pv # shell progress bar
    pistol # file preview
    # bat # cat with syntax highlighting
    lazygit # git tui
    tig # git tui
    dasel # transform data from csv/json/... (used by theme switcher)
    jq # json parser
    feh # image viewer
    neovim-remote # send commands to neovim instances (used by theme switcher)
    trash-cli # put files in trash instead of deleting them
    playerctl # control media players, like spotify, vlc via cli / keybindings
    pamixer # control pulseaudio via cli / keybindings
    fd # find files by filename, alternative to `find`
    tldr # quick command examples
    comma # run nix packages without installing them
    speedtest-cli
    gh # github cli
    autorandr # automatic monitor profiles
    xsel # clipboard
    xclip # clipboard
    tmate # invite someone else into your terminal via ssh
    imagemagick
    mediainfo
    entr # run commands when files change
    xcolor # simple color picker

    networkmanagerapplet
    xcwd # returns current directory of x application, used to spawn new termanals in the current directory: ~/bin/xcwd-home
    arandr # manage monitors

    # system tools
    man
    pciutils
    usbutils
    hdparm
    gparted
    ntfs3g
    ntfsprogs
    testdisk
    exfat
    lm_sensors
    linuxPackages.cpupower
    xorg.xkill
    psmisc
    wirelesstools
    xorg.xbacklight
    acpi
    samba
    cifs-utils
    mtpfs
    jmtpfs
    file
    smem

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
    pavucontrol
    light
    mimeo
    xdotool
    gnumake
    macchanger

    # development
    python3
    nodejs
    earthly # better Dockerfiles
    devbox # install dev tools in project
    sqlite-interactive

    # language servers/formatters/linters
    nixd # nix language server
    lua-language-server
    alejandra # nix code formatter
    # nodePackages.bash-language-server
    # shellcheck # shell language server
    # marksman # markdown language server

    # themeing
    polybar # status bar
    qogir-theme # gtk theme
    qogir-icon-theme # gtk theme
    elementary-xfce-icon-theme
    xsettingsd
    lxappearance
    libsForQt5.qtstyleplugins # gtk style for qt
    libsForQt5.qt5ct
    lxappearance
    ueberzugpp # view images in terminals without sixel support
    i3lock

    # guis

    vscode
    (jetbrains.plugins.addPlugins jetbrains.idea-community [
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/jetbrains/plugins/plugins.json
      "github-copilot"
    ])
    gcolor2
    screenkey # screencast tool to display key presses
    zoom-us # TODO
    vlc
    mpv
    neovide # neovim gui
    megasync # cloud file storage and sync
    krusader # file manager with good directory comparison
    keepassxc # password manager
    libsecret.out # secret-tool to retrieve secrets from keepassxc
    signal-desktop
    telegram-desktop
    spotify
    gthumb
    libreoffice
    sublime-merge
    skypeforlinux
  ];

  # home.stylix.image = ./downloads/wallpaper-desktop-latest.jpg

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "23.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
