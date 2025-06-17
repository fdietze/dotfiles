{ pkgs, ... }: {

  programs.bash.enable = true;
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.starship = {
    # https://starship.rs/config/
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = true;
    enableFishIntegration = true;
    settings = (with builtins;
      fromTOML (readFile
        "${pkgs.starship}/share/starship/presets/nerd-font-symbols.toml")) // {
          git_status.stashed = ""; # disable stash indicator
          python.disabled = true;
          rust.disabled = true;
          scala.disabled = true;
          java.disabled = true;
          julia.disabled = true;
          docker_context.disabled = true;
          dart.disabled = true;
          package.disabled = true; # do not show npm, cargo etc
          nodejs.disabled = true;
        };

  };

  programs.less.keys = ''
    # VIM
    j   forw-line
    k   back-line
    h   left-scroll
    l   right-scroll
    g   goto-line
    G   goto-end
    ^d  forw-scroll
    ^u  back-scroll
    ^f  forw-screen
    ^b  back-screen

    # NEO
    ^h  undo-hilite
    \   back-search
    ä quit

    #env
    LESS=' -icRS '
  '';

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
      G = "| rg -C 2";
      H = "| head";
      L = "| less";
      C = "| xclip -selection clipboard";
      N = ''"$(ls -tp | grep -v '/$' | head -1)"'';
    };

    initContent = ''
      # old:
      # https://github.com/dottr/dottr/tree/master/yolk/zsh
      # https://github.com/fdietze/dotfiles/blob/master/.zshrc.vimode



      # workaround for rust-analyzer not finding CC in nix shell
      export CC="gcc";


      setopt nonomatch # avoid the zsh "no matches found" / allows typing sbt ~compile
      setopt interactivecomments # allow comments in interactive shell
      setopt hash_list_all # rehash command path and completions on completion attempt
      setopt BANG_HIST                 # Treat the '!' character specially during expansion.
      setopt INC_APPEND_HISTORY        # Write to the history file immediately, not when the shell exits.
      setopt SHARE_HISTORY             # Share history between all sessions. <-- Disable this for now
      setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicate entries first when trimming history.
      setopt HIST_IGNORE_DUPS          # Don't record an entry that was just recorded again.
      setopt HIST_FIND_NO_DUPS         # Do not display a line previously found.
      setopt HIST_IGNORE_SPACE         # Don't record an entry starting with a space.
      setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks before recording entry.
      setopt HIST_VERIFY               # Don't execute immediately upon history expansion.
      # https://unix.stackexchange.com/questions/568907/why-do-i-lose-my-zsh-history
      HISTFILE=~/.zsh_history.local

      # history prefix search
      autoload -U history-search-end # have the cursor placed at the end of the line once you have selected your desired command
      bindkey '^[[A' history-beginning-search-backward
      bindkey '^[[B' history-beginning-search-forward

      # zsh with pwd in window title
      function precmd {
          echo -en "\007" # after every command, set the window to urgent, by ringing the bell
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
      export FZF_DEFAULT_OPTS="--extended --multi --ansi" # extended match and multiple selections
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
      export LESS_TERMCAP_mb="$(tput bold; tput setaf 6)";
      export LESS_TERMCAP_md="$(tput bold; tput setaf 2)";
      export LESS_TERMCAP_me="$(tput sgr0)";
      export LESS_TERMCAP_so="$(tput bold; tput setaf 0; tput setab 6)";
      export LESS_TERMCAP_se="$(tput rmso; tput sgr0)";
      export LESS_TERMCAP_us="$(tput smul; tput bold; tput setaf 3)";
      export LESS_TERMCAP_ue="$(tput rmul; tput sgr0)";
      export LESS_TERMCAP_mr="$(tput rev)";
      export LESS_TERMCAP_mh="$(tput dim)";
      export LESS_TERMCAP_ZN="$(tput ssubm)";
      export LESS_TERMCAP_ZV="$(tput rsubm)";
      export LESS_TERMCAP_ZO="$(tput ssupm)";
      export LESS_TERMCAP_ZW="$(tput rsupm)";
      export GROFF_NO_SGR=1;

      x() { # open a gui command and close the terminal
          zsh -i -c "$@ &; disown" 
          exit
      }

      cdg() {
          # Traverse upwards until you find a .git directory
          local dir=$(git rev-parse --show-toplevel 2>/dev/null)
          if [ -n "$dir" ]; then
              cd "$dir" || echo "Failed to change directory."
          else
              echo "Not a git repository."
          fi
      }

      eval "$(devbox global shellenv)"
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
      {
        name = "mill-zsh-completions";
        file = "mill-zsh-completions.plugin.zsh";
        src = pkgs.fetchFromGitHub {
          owner = "carlosedp";
          repo = "/mill-zsh-completions";
          rev = "3e66e19868bda2f361d6ea8cb8abb8ff91dcc920";
          sha256 = "sha256-6ZyRkg4eXh1JVtYRHTfxJ8ctdOLw4Ff8NsEqfpoxyfI=";
        };
      }
    ];
  };
}
