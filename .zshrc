source ~/.zprofile # because I have bash as my login shell
DISABLE_AUTO_UPDATE="true" # disable oh-my-zsh auto-update
source ~/local/zgen/zgen.zsh
export PURE_GIT_PULL=0

if ! zgen saved; then
    echo "creating zgen save..."
    zgen oh-my-zsh # oh-my-zsh default settings

    zgen load zsh-users/zsh-syntax-highlighting
    zgen load zsh-users/zsh-history-substring-search # needs to be loaded after highlighting
    zgen load rupa/z # jump to most used directories

    zgen load mafredri/zsh-async # for pure-prompt
    zgen load sindresorhus/pure # prompt
    zgen load b4b4r07/zsh-vimode-visual

    zgen load dottr/dottr
    zgen save
fi

# command not found for Arch
[ -r /etc/profile.d/cnf.sh ] && . /etc/profile.d/cnf.sh

# fzf fuzzy file matcher shell extensions
. /etc/profile.d/fzf.zsh

source ~/.sh_aliases


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
fry bind2maps


# renaming utils
autoload -U zmv

setopt nonomatch # avoid the zsh "no matches found" / allows sbt ~compile
setopt hash_list_all # rehash command path and completions on completion attempt

# we don't want no flow control, Ctrl-s / Ctrl-q
# this allows vim to map <C-s>
unsetopt flow_control
stty -ixon

source .zshrc.vimode
RPROMPT='${MODE_INDICATOR}'

setopt transient_rprompt # hide earlier rprompts

# bind UP and DOWN arrow keys
bind2maps vicmd viins -- "$terminfo[kcuu1]" history-substring-search-up
bind2maps vicmd viins -- "$terminfo[kcud1]" history-substring-search-down





