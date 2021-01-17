export PATH=$HOME/.npm-packages/bin:$PATH
export PATH=$HOME/.gem/bin:$PATH
export PATH=$HOME/.zgen/dottr/dottr-master/pan.git:$PATH
export PATH=$HOME/.cargo/bin:$PATH
export PATH=$HOME/go/bin:$PATH
export PATH=$HOME/bin:$PATH
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/.bloop:$PATH
export PATH=$HOME/development/flutter/bin:$PATH
# export PATH=$HOME/homebrew/bin:${PATH}
# if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi

export GEM_HOME=$HOME/.gem

# export GOPATH=~/go

export EDITOR=nvim

export NIX_AUTO_INSTALL=true # automatically installs and runs non-installed software in nix-shell (requires `programs.command-not-found.enable = true`)

# fix java apps in tiling window managers
export _JAVA_AWT_WM_NONREPARENTING=1

# fix java apps font rendering
# javaopts=$javaopts" -Dawt.useSystemAAFontSettings=gasp -Dsun.java2d.xrender=true -Dswing.aatext=true"
export AWT_TOOLKIT=MToolkit
export GDK_USE_XFT=1

export SBT_OPTS="-Xms1G -Xmx8G -Xss16M -XX:+CMSClassUnloadingEnabled -XX:+UseConcMarkSweepGC"

export RUST_BACKTRACE=1
