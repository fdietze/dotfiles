# export PATH=$HOME/.node_modules/bin:$PATH
# export PATH=$HOME/.gem/ruby/2.3.0/bin:$PATH
export PATH=$HOME/projects/dottr/pan.git:$PATH
export PATH=$HOME/.cargo/bin:$PATH
export PATH=$HOME/go/bin:$PATH
export PATH=$HOME/bin:$PATH

# export GOPATH=~/go
# export RUST_SRC_PATH=~/projects/rust/src
# export RUST_BACKTRACE=1

export EDITOR=nvim
export BROWSER=firefox
export DE=gnome

export NIX_AUTO_RUN=true # automatically installs and runs non-installed software in nix-shell (requires `programs.command-not-found.enable = true`)

# fix java apps in tiling window managers
# export _JAVA_AWT_WM_NONREPARENTING=1

# fix java apps font rendering
# javaopts=$javaopts" -Dawt.useSystemAAFontSettings=gasp -Dsun.java2d.xrender=true -Dswing.aatext=true"
export AWT_TOOLKIT=MToolkit
export GDK_USE_XFT=1

# https://github.com/chenkelmann/neo2-awt-hack
# wget https://github.com/chenkelmann/neo2-awt-hack/blob/master/releases/neo2-awt-hack-0.4-java8oracle.jar\?raw\=true -O ~/local/neo2-awt-hack-0.4-java8oracle.jar
export _JAVA_OPTIONS="-XX:+UseCompressedOops -Dawt.useSystemAAFontSettings=lcd -Xbootclasspath/p:$HOME/local/neo2-awt-hack-0.4-java8oracle.jar"

export SBT_OPTS="-Xms32M -Xmx1200M -Xss1M -XX:+CMSClassUnloadingEnabled -XX:+UseConcMarkSweepGC"
