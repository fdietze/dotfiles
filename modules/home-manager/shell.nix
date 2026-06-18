{
  config,
  lib,
  pkgs,
  hostLabel ? "",
  ...
}: let
  # SSH-only host label for the prompt (starship env_var module below). The OS
  # hostname is useless on some boxes — korken/nix-on-droid reports "localhost"
  # under proot — so each deployment passes a stable hostLabel. Standalone HM on
  # arbitrary boxes leaves it empty and falls back to the shell's runtime
  # hostname ($HOSTNAME in bash, $HOST in zsh).
  #
  # Shown only when "remote": an SSH session, or a Fly Sprite (always-remote
  # microVM accessed via the sprite proxy, not SSH — marked by the /.sprite dir).
  sshHostInit = ''
    if [ -n "$SSH_CONNECTION" ] || [ -d /.sprite ]; then
      export STARSHIP_HOST=${lib.escapeShellArg hostLabel}
      [ -n "$STARSHIP_HOST" ] || STARSHIP_HOST="''${HOSTNAME:-$HOST}"
    fi
  '';
in {
  programs.bash = {
    enable = true;
    initExtra = sshHostInit;
  };
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.starship = {
    # https://starship.rs/config/
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    enableIonIntegration = true;
    settings =
      (
        with builtins; fromTOML (readFile "${pkgs.starship}/share/starship/presets/nerd-font-symbols.toml")
      )
      // {
        # Each prompt scans the CWD's files to decide which language/tool modules
        # to show. Default budget is 30ms; bump it so big or slow dirs (e.g.
        # $HOME on nix-on-droid's slow storage) don't trip "scan timed out".
        # https://starship.rs/config/#prompt
        scan_timeout = 100;
        # Built-in hostname uses gethostname() — "localhost" under proot on
        # korken — so disable it and show the SSH-only STARSHIP_HOST label
        # instead ($all already renders $env_var). https://starship.rs/config/#environment-variable
        hostname.disabled = true;
        env_var.STARSHIP_HOST.format = "[@$env_value]($style) ";
        env_var.STARSHIP_HOST.style = "bold green";
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
        c.disabled = true;
        cpp.disabled = true;
      };
  };

  programs.less.config = ''
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
      # zshoptions(1): SHARE_HISTORY already appends history and should not be
      # combined with INC_APPEND_HISTORY. zsh has no native unbounded history,
      # so use a practical upper bound.
      size = 1000000000;
      save = size;
      path = "${config.home.homeDirectory}/.zsh_history.local";
      extended = true; # save timestamps
      share = true;
      expireDuplicatesFirst = true;
      findNoDups = true;
    };

    shellGlobalAliases = {
      G = "| rg -C 2";
      H = "| head";
      L = "| less";
      C = "| xclip -selection clipboard";
      N = ''"$(\ls -tr | tail -1)"'';
    };

    initContent = ''
      ${sshHostInit}
      # Claude Code spawns `$SHELL -i` at startup and dumps all aliases /
      # functions into ~/.claude/shell-snapshots/<file>.sh, which it sources
      # before every Bash tool call. This makes Claude see e.g. `cat=bat`
      # and get confused. The snapshot generator sources $HOME/.zshrc
      # directly (ZDOTDIR is ignored on that codepath, verified via strings
      # /nix/store/.../claude-code/bin/.claude-wrapped). Short-circuit here
      # so Claude's snapshot stays empty; interactive sessions are
      # unaffected because CLAUDECODE is only set by the Claude CLI.
      [[ -n "$CLAUDECODE" ]] && return

      # old:
      # https://github.com/dottr/dottr/tree/master/yolk/zsh
      # https://github.com/fdietze/dotfiles/blob/master/.zshrc.vimode



      # workaround for rust-analyzer not finding CC in nix shell
      export CC="gcc";


      setopt nonomatch # avoid the zsh "no matches found" / allows typing sbt ~compile
      setopt interactivecomments # allow comments in interactive shell
      setopt hash_list_all # rehash command path and completions on completion attempt
      setopt BANG_HIST                 # Treat the '!' character specially during expansion.
      setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks before recording entry.
      setopt HIST_VERIFY               # Don't execute immediately upon history expansion.

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

      # in zshrc: 10ms timeout waiting for keysequences
      export KEYTIMEOUT=1



      export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
      export FZF_DEFAULT_OPTS="--extended --multi --ansi" # extended match and multiple selections
      export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
      export FZF_CTRL_T_OPTS="--tac --height 90% --reverse --preview 'pistol {} \$FZF_PREVIEW_COLUMNS \$FZF_PREVIEW_LINES' --bind 'ctrl-d:preview-page-down,ctrl-r:reload($FZF_CTRL_T_COMMAND)"


      insertCommitHash () {
        commits=$($HOME/projects/dotfiles/home/bin/git-select-commit)
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


      # Git worktree selector with fzf
      # https://brtkwr.com/posts/2025-12-17-git-worktree-fzf-helper/
      wt() {
        local create=false
        local delete=false
        local copy_envrc=false
        local name=""
        local target=""

        _wt_usage() {
          cat <<USAGE
      Usage: wt [-c <name>] [-e] [-d [path]] [-h]

      Options:
        -c <name>   Create a new worktree with branch name <name>
        -e          Copy .envrc from root and run direnv allow (use with -c)
        -d [path]   Delete a worktree (fuzzy select if no path given, use '.' for current)
        -h          Show this help message
      USAGE
        }

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -c) create=true; name="$2"; shift 2 ;;
            -e) copy_envrc=true; shift ;;
            -d) delete=true; shift; [[ $# -gt 0 && ! "$1" =~ ^- ]] && { target="$1"; shift; } ;;
            -h) _wt_usage; return 0 ;;
            *) _wt_usage; return 1 ;;
          esac
        done

        if ($create || $copy_envrc) && $delete; then
          echo "Error: -c/-e and -d are mutually exclusive"; return 1
        fi

        if $create; then
          [[ -z "$name" ]] && { echo "Error: -c requires a name"; return 1; }
          local root=$(git rev-parse --show-toplevel)
          local new_path="$root/$name"
          git worktree add "$new_path" -b "$name" && cd "$new_path"
          if $copy_envrc && [[ -f "$root/.envrc" ]]; then
            cp "$root/.envrc" "$new_path/.envrc"
            direnv allow
          fi
        elif $delete; then
          local to_delete
          if [[ -n "$target" ]]; then
            to_delete=$(realpath "$target")
          else
            to_delete=$(git worktree list | fzf --height 40% --reverse | awk '{print $1}')
          fi
          [[ -z "$to_delete" ]] && return 0
          local main_wt=$(git worktree list | head -1 | awk '{print $1}')
          if [[ "$to_delete" == "$main_wt" ]]; then
            echo "Error: cannot delete main worktree"; return 1
          fi
          [[ "$(realpath .)" == "$to_delete"* ]] && cd "$main_wt"
          git worktree remove "$to_delete"
        else
          local selected=$(git worktree list | fzf --height 40% --reverse | awk '{print $1}')
          [[ -n "$selected" ]] && cd "$selected"
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
          repo = "mill-zsh-completions";
          rev = "3e66e19868bda2f361d6ea8cb8abb8ff91dcc920";
          sha256 = "sha256-zmWTT65HlVsvFTGzs5SQsVqSHc1XaLwCHmiWZgkZsCU=";
        };
      }
    ];
  };
}
