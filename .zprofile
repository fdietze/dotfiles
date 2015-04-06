[[ -e ~/.profile ]] && emulate sh -c 'source ~/.profile'

# color wrappers for common commands
export PATH=$(cope_path):$PATH

# colorful file listings
eval $(dircolors ~/.dir_colors)

# syntax highlighting for less
# export LESSOPEN="| /usr/bin/src-hilite-lesspipe.sh %s" # package: source-highlight
export LESSOPEN="| highlight %s -O ansi" # package: highlight-gui
export LESS=' -R '

# colorize manpages
export LESS_TERMCAP_mb=$(printf "\33[01;34m")   # begin blinking
export LESS_TERMCAP_md=$(printf "\33[01;34m")   # begin bold
export LESS_TERMCAP_me=$(printf "\33[0m")       # end mode
export LESS_TERMCAP_se=$(printf "\33[0m")       # end standout-mode
export LESS_TERMCAP_so=$(printf "\33[44;1;37m") # begin standout-mode - info box
export LESS_TERMCAP_ue=$(printf "\33[0m")       # end underline
export LESS_TERMCAP_us=$(printf "\33[01;35m")   # begin underline

# fzf fuzzy file finder
export FZF_DEFAULT_COMMAND='ag -l --hidden -g ""'
export FZF_DEFAULT_OPTS="-x -m --ansi" # extended match and multiple selections

