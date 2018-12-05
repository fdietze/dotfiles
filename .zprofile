[[ -e ~/.profile ]] && emulate sh -c 'source ~/.profile'

# color wrappers for common commands
which cope_path > /dev/null && export PATH=$(cope_path):$PATH

# colorful file listings
eval $(dircolors ~/.dir_colors)

# vimpager instead of less
# export PAGER=/usr/bin/vimpager
export PAGER="less -R -F"

# colorize manpages (when using less as pager)
export LESS_TERMCAP_mb=$(printf "\33[01;34m")   # begin blinking
export LESS_TERMCAP_md=$(printf "\33[01;34m")   # begin bold
export LESS_TERMCAP_me=$(printf "\33[0m")       # end mode
export LESS_TERMCAP_se=$(printf "\33[0m")       # end standout-mode
export LESS_TERMCAP_so=$(printf "\33[44;1;37m") # begin standout-mode - info box
export LESS_TERMCAP_ue=$(printf "\33[0m")       # end underline
export LESS_TERMCAP_us=$(printf "\33[01;35m")   # begin underline

# fzf fuzzy file finder
# .git is ignored via ~/.agignore
export FZF_DEFAULT_COMMAND='ag --hidden -g ""'
export FZF_DEFAULT_OPTS="-x -m --ansi --exit-0 --select-1" # extended match and multiple selections
