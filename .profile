export PATH=$HOME/.node_modules/bin:$PATH
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
export PATH=$HOME/projects/dottr/pan.git:$PATH
export PATH=$HOME/bin:$PATH

export GOPATH=~/go
export RUST_SRC_PATH=~/projects/rust/src

export EDITOR=vim
export BROWSER=qutebrowser
export DE=gnome

# fix java apps in tiling window managers
export _JAVA_AWT_WM_NONREPARENTING=1

# fix java apps font rendering
javaopts=$javaopts" -Dawt.useSystemAAFontSettings=gasp -Dsun.java2d.xrender=true -Dswing.aatext=true"
export AWT_TOOLKIT=MToolkit
export GDK_USE_XFT=1

sbtopts=$sbtopts" -Xms32M -Xmx712M -Xss1M -XX:+CMSClassUnloadingEnabled -XX:+UseConcMarkSweepGC"
javaopts=$javaopts" -XX:+UseCompressedOops"

# sbt-web: use native Node.js instead of Trireme
# https://www.playframework.com/documentation/2.3.x/Migration23
sbtopts=$sbtopts" -Dsbt.jse.engineType=Node"

export _JAVA_OPTIONS=$javaopts
export SBT_OPTS=$sbtopts
