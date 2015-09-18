source ~/.zprofile # because I have bash as my login shell
DISABLE_AUTO_UPDATE="true" # disable oh-my-zsh auto-update
source /usr/share/zsh/scripts/zgen/zgen.zsh
export PURE_GIT_PULL=0

if ! zgen saved; then
    echo "creating zgen save..."
    zgen oh-my-zsh # oh-my-zsh default settings

    zgen load zsh-users/zsh-syntax-highlighting
    zgen load zsh-users/zsh-history-substring-search # needs to be loaded after highlighting
    zgen load jimhester/per-directory-history
    zgen load rupa/z # jump to most used directories

    zgen load tarruda/zsh-autosuggestions

    # instant auto completion
    # zgen load hchbaw/auto-fu.zsh
    # zle-line-init () {auto-fu-init;}; zle -N zle-line-init
    # zstyle ':completion:*' completer _oldlist _complete
    # zle -N zle-keymap-select auto-fu-zle-keymap-select

    zgen load mafredri/zsh-async # for pure-prompt
    zgen load sindresorhus/pure # prompt

    zgen load dottr/dottr
    zgen save
fi

# bind UP and DOWN arrow keys
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down


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
fry daytime
fry interactive-mv
fry cd-tmp
fry cd-git-root
fry neo4j-query
NEO4J_QUERY_JSON_FORMATTER="underscore print --color --outfmt json"
fry mkdir-cd


# command not found for Arch
[ -r /etc/profile.d/cnf.sh ] && . /etc/profile.d/cnf.sh

source ~/.sh_aliases

# renaming utils
autoload -U zmv

setopt nonomatch # avoid the zsh "no matches found" / allows sbt ~compile
setopt hash_list_all # rehash command path and completions on completion attempt

# Vi-mode for zsh
# bindkey -v
# export KEYTIMEOUT=1



[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

