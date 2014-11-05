
# fix java apps in tiling window managers
export _JAVA_AWT_WM_NONREPARENTING=1

# export AWT_TOOLKIT=XToolkit

#JAVA_HOME=/opt/java7
export PATH=$HOME/bin:$PATH
export PATH=/usr/lib/jvm/java-7-openjdk/bin:$PATH
export PATH=/home/felix/local/android-studio/sdk/tools:$PATH
export PATH=/home/felix/local/android-studio/sdk/platform-tools:$PATH
export GOPATH=~/go

export BROWSER=chromium
export EDITOR=vim
export DE=mate

export PATH=$(cope_path):$PATH

# syntax highlighting for less
# export LESSOPEN="| /usr/bin/src-hilite-lesspipe.sh %s" # package: source-highlight
export LESSOPEN="| highlight %s -O ansi" # package: highlight-gui
export LESS=' -R '

