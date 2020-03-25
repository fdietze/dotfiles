[[ -e ~/.zprofile ]] && emulate sh -c 'source ~/.zprofile'

export DISABLE_AUTO_UPDATE="true" # disable oh-my-zsh auto-update
export DISABLE_UPDATE_PROMPT="true" # disable oh-my-zsh update prompt
export ZSH_THEME="" # disable oh-my-zsh themes
ZSH_DISABLE_COMPFIX=true

source "${HOME}/.zgen/zgen.zsh"
if ! zgen saved; then
    echo "creating zgen save..."
    zgen oh-my-zsh # oh-my-zsh default settings

    zgen load rupa/z # jump to most used directories

    zgen load denysdovhan/spaceship-prompt spaceship
    zgen load b4b4r07/zsh-vimode-visual

    zgen load dottr/dottr

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

# needed for bind2maps
typeset -A key
key=(
Home     "${terminfo[khome]}"
End      "${terminfo[kend]}"
Insert   "${terminfo[kich1]}"
Delete   "${terminfo[kdch1]}"
Backspace "^?"
Up       "${terminfo[kcuu1]}"
Down     "${terminfo[kcud1]}"
Left     "${terminfo[kcub1]}"
Right    "${terminfo[kcuf1]}"
PageUp   "${terminfo[kpp]}"
PageDown "${terminfo[knp]}"
BackTab  "${terminfo[kcbt]}"
)


fry bell-on-precmd
fry completion
fry ncserve
fry alias-usage-analysis
fry print-expanded-alias
# fry vim-open-files-at-lines
fry search-select-edit
fry git-select-commit
fry git-onstage
fry github-clone
fry interactive-mv
fry cd-tmp
fry cd-git-root
fry mkdir-cd
fry screencapture
fry transcode-video
fry bind2maps
fry git-dirty-files-command
fry watchdo
fry nvim-rpc

setopt nonomatch # avoid the zsh "no matches found" / allows sbt ~compile
setopt hash_list_all # rehash command path and completions on completion attempt
setopt transient_rprompt # hide earlier rprompts
unsetopt flow_control # we dont want no flow control, Ctrl-s / Ctrl-q, this allows vim to map <C-s>
stty -ixon # (belongs to flow control option)
autoload -U zmv # renaming utils

# activate vi modes and display mode indicator in prompt
source ~/.zshrc.vimode
RPROMPT='${MODE_INDICATOR}'

bind2maps emacs viins vicmd -- -s '^[[1;5C' forward-word
bind2maps emacs viins vicmd -- -s '^[[1;5D' backward-word

autoload edit-command-line
zle -N edit-command-line
bind2maps vicmd viins -- -s '^v' edit-command-line

autoload bashcompinit && bashcompinit

# history prefix search
autoload -U history-search-end # have the cursor placed at the end of the line once you have selected your desired command
# zle -N history-beginning-search-backward-end history-search-end
# zle -N history-beginning-search-forward-end history-search-end
# bind2maps emacs viins vicmd -- "Up" history-substring-search-up
# bind2maps emacs viins vicmd -- "Down" history-substring-search-down

bind2maps emacs viins vicmd -- "Up" up-line-or-search
bind2maps emacs viins vicmd -- "Down" down-line-or-search

# if [ -n "${commands[fzf-share]}" ]; then
#     source "$(fzf-share)/key-bindings.zsh"
#     source "$(fzf-share)/completion.zsh"
# fi

source ~/.sh_aliases
