source ~/.zprofile # because I have bash as my login shell

# Path to your oh-my-zsh installation.
ZSH=/usr/share/oh-my-zsh/

# Uncomment the following line to disable bi-weekly auto-update checks.
DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
git
cp
history-substring-search
systemd
web-search
heroku
sbt
scala
per-directory-history
)
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh

source $ZSH/oh-my-zsh.sh
# User configuration

source ~/projects/dottr/pan.zsh
fry ncserve
fry pacman-disowned
fry alias-usage-analysis
fry print-expanded-alias
fry vim-open-files-at-lines
fry search-select-edit
fry git-select-commit
fry git-onstage
fry daytime
fry interactive-mv
fry cd-tmp
fry cd-git-root
fry neo4j-query
NEO4J_QUERY_JSON_FORMATTER="underscore print --color --outfmt json"

source ~/.sh_aliases

# renaming utils
autoload -U zmv

}

# set prompt theme
source ~/.oh-my-zsh/themes/slim.zsh-theme

# z (changing directories fast: https://github.com/rupa/z/)
. ~/bin/z.sh

# command not found for Arch
[ -r /etc/profile.d/cnf.sh ] && . /etc/profile.d/cnf.sh


