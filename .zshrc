source ~/.zprofile # because I have bash as my login shell
DISABLE_AUTO_UPDATE="true" # disable oh-my-zsh auto-update
source ~/local/zgen/zgen.zsh
export PURE_GIT_PULL=0

if ! zgen saved; then
    echo "creating zgen save..."
    zgen oh-my-zsh # oh-my-zsh default settings
    zgen load b4b4r07/zsh-vimode-visual

    zgen load zsh-users/zsh-syntax-highlighting
    zgen load zsh-users/zsh-history-substring-search # needs to be loaded after highlighting
    zgen load rupa/z # jump to most used directories

    zgen load mafredri/zsh-async # for pure-prompt
    zgen load sindresorhus/pure # prompt

    zgen load dottr/dottr
    zgen save
fi

# VI mode for zsh
bindkey -v
export KEYTIMEOUT=1 # reduce ESC key delay to 0.01s

# implement replace mode
bindkey -N virep viins
bindkey -M vicmd "R" overwrite-mode
overwrite-mode() {
  zle -K virep
  zle .overwrite-mode
}
zle -N overwrite-mode

# VI mode indicator
RPROMPT=""

function zle-keymap-select {
    case $KEYMAP in
        main|viins  ) RPROMPT="%{$bg[green]%}%{$fg[white]%}%B I %{$reset_color%}" ;;
        vicmd       ) RPROMPT="%{$bg[blue]%}%{$fg[white]%}%B N %{$reset_color%}" ;;
        vivis|vivli ) RPROMPT="%{$bg[magenta]%}%{$fg[white]%}%B V %{$reset_color%}" ;;
        virep       ) RPROMPT="%{$bg[red]%}%{$fg[white]%}%B R %{$reset_color%}" ;;
    esac
    zle reset-prompt
}
zle -N zle-keymap-select

# always start in insert mode
function zle-line-init {
    zle vi-insert
    zle zle-keymap-select
    zle reset-prompt
}

# clear old indicator
function zle-line-finish {
    RPROMPT=""
    zle reset-prompt
}

# Fix a bug when you C-c in CMD mode and you'd be prompted with CMD mode indicator, while in fact you would be in INS mode
# Fixed by catching SIGINT (C-c), set vim_mode to INS and then repropagate the SIGINT, so if anything else depends on it, we will not break it
function TRAPINT() {
    zle zle-line-finish
    return $(( 128 + $1 ))
} 


bindkey -M vicmd "${terminfo[kend]}" end-of-line
bindkey -M viins "${terminfo[kend]}" end-of-line
# bindkey -M vivis "${terminfo[kend]}" vi-visual-eol
bindkey -M vicmd "${terminfo[khome]}" beginning-of-line
bindkey -M viins "${terminfo[khome]}" beginning-of-line
# bindkey -M vivis "${terminfo[khome]}" vi-visual-bol
bindkey -M viins "^?" backward-delete-char
bindkey -M viins "^[[3~" delete-char
bindkey -M viins "^W" backward-kill-word 

# bind UP and DOWN arrow keys
bindkey -M vicmd "$terminfo[kcuu1]" history-substring-search-up
bindkey -M viins "$terminfo[kcuu1]" history-substring-search-up
bindkey -M vicmd "$terminfo[kcud1]" history-substring-search-down
bindkey -M viins "$terminfo[kcud1]" history-substring-search-down

bindkey -M vicmd 'V'  vi-vlines-mode
bindkey -M vicmd 'v'  vi-visual-mode



fry completion
fry ncserve
fry pacman-disowned
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
fry neo4j-query
NEO4J_QUERY_JSON_FORMATTER="underscore print --color --outfmt json"
fry mkdir-cd
fry screencapture
fry transcode-video


# command not found for Arch
[ -r /etc/profile.d/cnf.sh ] && . /etc/profile.d/cnf.sh

# fzf fuzzy file matcher shell extensions
. /etc/profile.d/fzf.zsh

source ~/.sh_aliases

# renaming utils
autoload -U zmv

setopt nonomatch # avoid the zsh "no matches found" / allows sbt ~compile
setopt hash_list_all # rehash command path and completions on completion attempt

# we don't want no flow control, Ctrl-s / Ctrl-q
# this allows vim to map <C-s>
unsetopt flow_control
stty -ixon

