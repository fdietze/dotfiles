export EDITOR=vim
export BROWSER=qutebrowser
export DE=mate

# fix java apps in tiling window managers
export _JAVA_AWT_WM_NONREPARENTING=1
# export _JAVA_OPTIONS="-Dawt.useSystemAAFontSettings=off -Dsun.java2d.xrender=true"
# export AWT_TOOLKIT=XToolkit

export GDK_USE_XFT=1

export GOPATH=~/go
export RUST_SRC_PATH=~/projects/rust/src

export SBT_OPTS="-Xms64M -Xmx256M -Xss1M -XX:+CMSClassUnloadingEnabled"
export _JAVA_OPTIONS="-XX:+UseCompressedOops"

# sbt-web: use native Node.js instead of Trireme
# https://www.playframework.com/documentation/2.3.x/Migration23
export SBT_OPTS="$SBT_OPTS -Dsbt.jse.engineType=Node"
