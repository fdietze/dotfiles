export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8


export PATH=$HOME/bin:$PATH
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/.npm-packages/bin:$PATH
export PATH=$HOME/.cargo/bin:$PATH
export PATH=$HOME/go/bin:$PATH
export PATH=$HOME/development/flutter/bin:$PATH
export PATH=$HOME/.local/share/coursier/bin:$PATH
export PATH=$HOME/.zgenom/sources/dottr/dottr/___/pan.git:$PATH # https://github.com/dottr/dottr/#installation-1
# export PATH=$HOME/homebrew/bin:${PATH}
# if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi
[ -f ~/projects/ubunix/ubunix.sh ] && source ~/projects/ubunix/ubunix.sh

# install ruby gems in user-space
export GEM_HOME=$HOME/.gem
export PATH=$HOME/.gem/bin:$PATH

export EDITOR=nvim
export BROWSER=firefox


# automatically installs and runs non-installed software in nix-shell (requires `programs.command-not-found.enable = true`)
export NIX_AUTO_INSTALL=true 
export NIX_AUTO_RUN=true

# fix java apps in tiling window managers
export _JAVA_AWT_WM_NONREPARENTING=1

# fix java apps font rendering
# javaopts=$javaopts" -Dawt.useSystemAAFontSettings=gasp -Dsun.java2d.xrender=true -Dswing.aatext=true"
export AWT_TOOLKIT=MToolkit
export GDK_USE_XFT=1
export QT_QPA_PLATFORMTHEME=gtk2

export SBT_OPTS="-Xms128M -Xmx3G -Xss16M"
# export SBT_NATIVE_CLIENT="true" # automatically reuse existing sbt sessions

export RUST_BACKTRACE=1


export PAGER="less --RAW-CONTROL-CHARS" # less with colors

# colorize less
export LESS_TERMCAP_mb=$(tput bold; tput setaf 6)
export LESS_TERMCAP_md=$(tput bold; tput setaf 2)
export LESS_TERMCAP_me=$(tput sgr0)
export LESS_TERMCAP_so=$(tput bold; tput setaf 0; tput setab 6)
export LESS_TERMCAP_se=$(tput rmso; tput sgr0)
export LESS_TERMCAP_us=$(tput smul; tput bold; tput setaf 3)
export LESS_TERMCAP_ue=$(tput rmul; tput sgr0)
export LESS_TERMCAP_mr=$(tput rev)
export LESS_TERMCAP_mh=$(tput dim)
export LESS_TERMCAP_ZN=$(tput ssubm)
export LESS_TERMCAP_ZV=$(tput rsubm)
export LESS_TERMCAP_ZO=$(tput ssupm)
export LESS_TERMCAP_ZW=$(tput rsupm)
export GROFF_NO_SGR=1
