export PATH=$HOME/.node_modules/bin:$PATH
# export PATH=$HOME/.gem/ruby/2.3.0/bin:$PATH
export PATH=$HOME/projects/dottr/pan.git:$PATH
# export PATH=$HOME/.multirust/toolchains/nightly/cargo/bin:$PATH
export PATH=$HOME/go/bin:$PATH
export PATH=$HOME/bin:$PATH
export PATH=$HOME/bin:$PATH
export PATH=$HOME/local/neo4j/bin:$PATH

export GOPATH=~/go
export RUST_SRC_PATH=~/projects/rust/src
export RUST_BACKTRACE=1

export EDITOR=vim
export BROWSER=chromium
export DE=gnome

# fix java apps in tiling window managers
export _JAVA_AWT_WM_NONREPARENTING=1

# fix java apps font rendering
# javaopts=$javaopts" -Dawt.useSystemAAFontSettings=gasp -Dsun.java2d.xrender=true -Dswing.aatext=true"
export AWT_TOOLKIT=MToolkit
export GDK_USE_XFT=1

sbtopts="$sbtopts -Xms32M -Xmx712M -Xss1M -XX:+CMSClassUnloadingEnabled -XX:+UseConcMarkSweepGC"
# javaopts=$javaopts" -XX:+UseCompressedOops"

# sbt-web: use native Node.js instead of Trireme
# https://www.playframework.com/documentation/2.3.x/Migration23
sbtopts="$sbtopts -Dsbt.jse.engineType=Node"

# export _JAVA_OPTIONS=$javaopts
export SBT_OPTS="$sbtopts"
