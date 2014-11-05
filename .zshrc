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
plugins=(git archlinux cp history-substring-search systemd web-search heroku sbt scala)
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh

source $ZSH/oh-my-zsh.sh
# User configuration

# set prompt theme
source ~/.oh-my-zsh/themes/slim.zsh-theme

# z (changing directories fast: https://github.com/rupa/z/)
. ~/bin/z.sh

# command not found for Arch
[ -r /etc/profile.d/cnf.sh ] && . /etc/profile.d/cnf.sh

# colorful file listings
eval $(dircolors ~/.dir_colors)

# colorize manpages
export LESS_TERMCAP_mb=$(printf "\33[01;34m")   # begin blinking
export LESS_TERMCAP_md=$(printf "\33[01;34m")   # begin bold
export LESS_TERMCAP_me=$(printf "\33[0m")       # end mode
export LESS_TERMCAP_se=$(printf "\33[0m")       # end standout-mode
export LESS_TERMCAP_so=$(printf "\33[44;1;37m") # begin standout-mode - info box
export LESS_TERMCAP_ue=$(printf "\33[0m")       # end underline
export LESS_TERMCAP_us=$(printf "\33[01;35m")   # begin underline

# load custom aliases
source ~/.sh_aliases
