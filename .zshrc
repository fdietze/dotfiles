[[ -e ~/.profile ]] && emulate sh -c 'source ~/.profile'

export PAGER="less --RAW-CONTROL-CHARS" # less with colors

# colorize manpages (when using less as pager)
export LESS_TERMCAP_mb=$(printf "\33[01;34m")   # begin blinking
export LESS_TERMCAP_md=$(printf "\33[01;34m")   # begin bold
export LESS_TERMCAP_me=$(printf "\33[0m")       # end mode
export LESS_TERMCAP_se=$(printf "\33[0m")       # end standout-mode
export LESS_TERMCAP_so=$(printf "\33[44;1;37m") # begin standout-mode - info box
export LESS_TERMCAP_ue=$(printf "\33[0m")       # end underline
export LESS_TERMCAP_us=$(printf "\33[01;35m")   # begin underline


export DISABLE_AUTO_UPDATE="true" # disable oh-my-zsh auto-update
export DISABLE_UPDATE_PROMPT="true" # disable oh-my-zsh update prompt
export ZSH_THEME="" # disable oh-my-zsh themes
export DISABLE_MAGIC_FUNCTIONS=true # fix slow paste in zsh
ZSH_DISABLE_COMPFIX=true

source "${HOME}/.zgen/zgen.zsh"
if ! zgen saved; then
    echo "creating zgen save..."
    zgen oh-my-zsh # oh-my-zsh default settings

    zgen load rupa/z # jump to most used directories
    zgen load dottr/dottr

    zgen load denysdovhan/spaceship-prompt spaceship
    zgen load joel-porquet/zsh-dircolors-solarized.git
    zgen load zsh-users/zsh-autosuggestions
    zgen load zsh-users/zsh-syntax-highlighting # order is important (https://github.com/zsh-users/zsh-syntax-highlighting#why-must-zsh-syntax-highlightingzsh-be-sourced-at-the-end-of-the-zshrc-file)
    zgen load jeffreytse/zsh-vi-mode
    # zgen load kutsan/zsh-system-clipboard
    # zgen load b4b4r07/zsh-vimode-visual

    zgen save
fi

SPACESHIP_PROMPT_ORDER=(
  time          # Time stamps section
  user          # Username section
  dir           # Current directory section
  host          # Hostname section
  git           # Git section (git_branch + git_status)
  # hg            # Mercurial section (hg_branch  + hg_status)
  package       # Package version
  # node          # Node.js section
  # ruby          # Ruby section
  # elixir        # Elixir section
  # xcode         # Xcode section
  # swift         # Swift section
  # golang        # Go section
  # php           # PHP section
  rust          # Rust section
  haskell       # Haskell Stack section
  julia         # Julia section
  # docker        # Docker section
  aws           # Amazon Web Services section
  venv          # virtualenv section
  conda         # conda virtualenv section
  pyenv         # Pyenv section
  ubunix
  nixshell
  # dotnet        # .NET section
  # ember         # Ember.js section
  # terraform     # Terraform workspace section
  exec_time     # Execution time
  line_sep      # Line break
  battery       # Battery level and status
  # vi_mode       # Vi-mode indicator
  jobs          # Background jobs indicator
  exit_code     # Exit code section
  char          # Prompt character
)
SPACESHIP_CHAR_SYMBOL="❯ "
SPACESHIP_GIT_STATUS_STASHED=""

# ubunix spaceship prompt
SPACESHIP_UBUNIX_SHOW="${SPACESHIP_UBUNIX_SHOW=true}"
SPACESHIP_UBUNIX_PREFIX="${SPACESHIP_UBUNIX_PREFIX="in "}"
SPACESHIP_UBUNIX_SUFFIX="${SPACESHIP_UBUNIX_SUFFIX="$SPACESHIP_PROMPT_DEFAULT_SUFFIX"}"
SPACESHIP_UBUNIX_SYMBOL="${SPACESHIP_UBUNIX_SYMBOL="UBUNIX "}"
spaceship_ubunix() {
  [[ $SPACESHIP_UBUNIX_SHOW == false ]] && return

  [[ -z $UBUNIX ]] && return

  spaceship::section \
    "yellow" \
    "$SPACESHIP_UBUNIX_PREFIX" \
    "$SPACESHIP_UBUNIX_SYMBOL" \
    "$SPACESHIP_UBUNIX_SUFFIX"
}


# nix shell spaceship prompt
SPACESHIP_NIXSHELL_SHOW="${SPACESHIP_NIXSHELL_SHOW=true}"
SPACESHIP_NIXSHELL_PREFIX="${SPACESHIP_NIXSHELL_PREFIX=""}"
SPACESHIP_NIXSHELL_SUFFIX="${SPACESHIP_NIXSHELL_SUFFIX="($IN_NIX_SHELL) $SPACESHIP_PROMPT_DEFAULT_SUFFIX"}"
SPACESHIP_NIXSHELL_SYMBOL="${SPACESHIP_NIXSHELL_SYMBOL="Nix-Shell "}"
spaceship_nixshell() {
  [[ $SPACESHIP_NIXSHELL_SHOW == false ]] && return

  [[ -z $IN_NIX_SHELL ]] && return

  spaceship::section \
    "yellow" \
    "$SPACESHIP_NIXSHELL_PREFIX" \
    "$SPACESHIP_NIXSHELL_SYMBOL" \
    "$SPACESHIP_NIXSHELL_SUFFIX"
}

ZSH_AUTOSUGGEST_STRATEGY=(history)

fry bell-on-precmd
# fry completion
# fry ncserve
# fry alias-usage-analysis
fry print-expanded-alias
# # fry vim-open-files-at-lines
fry search-select-edit
fry git-select-commit
# fry git-onstage
fry github-clone
# fry interactive-mv
fry cd-tmp
fry cd-git-root
# fry mkdir-cd
# fry screencapture
# fry transcode-video
fry bind2maps
# fry git-dirty-files-command
# fry watchdo
# fry nvim-rpc

setopt nonomatch # avoid the zsh "no matches found" / allows sbt ~compile
setopt hash_list_all # rehash command path and completions on completion attempt
setopt transient_rprompt # hide earlier rprompts
setopt hist_ignore_dups # don't save consecutive duplicate commands
unsetopt flow_control # we dont want no flow control, Ctrl-s / Ctrl-q, this allows vim to map <C-s>
stty -ixon # (belongs to flow control option)
autoload -U zmv # renaming utils
autoload bashcompinit && bashcompinit
# history prefix search
autoload -U history-search-end # have the cursor placed at the end of the line once you have selected your desired command

# source ~/.zshrc.vimode
# map HOME/END in vi mode
bindkey -M viins "^[[H" beginning-of-line
bindkey -M viins  "^[[F" end-of-line
bindkey -M vicmd "^[[H" beginning-of-line
bindkey -M vicmd "^[[F" end-of-line
bindkey -M visual "^[[H" beginning-of-line
bindkey -M visual "^[[F" end-of-line



source ~/.sh_aliases

# fix fzf with zsh-vi-mode
# https://github.com/jeffreytse/zsh-vi-mode/issues/4#issuecomment-757234569
zvm_after_init_commands+=('source ~/.zshrc.fzf')




[ -f ~/projects/ubunix/ubunix.sh ] && source ~/projects/ubunix/ubunix.sh

eval "$(direnv hook zsh)" # load environment vars depending on directory https://direnv.net/docs/hook.html#zsh

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8  


