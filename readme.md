# How I use my computer

```bash
# install:
# zsh, ag, fzf, diff-so-fancy
# termite, xcwd, unclutter-xfixes, redshift

mkdir -p ~/projects
git clone --bare git@github.com:fdietze/dotfiles.git projects/dotfiles
GIT_DIR=$HOME/projects/dotfiles GIT_WORK_TREE=$HOME git checkout master

git clone https://github.com/tarjoilija/zgen.git "${HOME}/.zgen"
chsh -s /bin/zsh

ln -sf $HOME/.vim $HOME/.config/nvim
ln -sf $HOME/.vimrc $HOME/.vim/init.vim
vim +PlugInstall

ssh-keygen -t ed25519
```

* managing dotfiles with pure git + external worktree in $HOME
* fzf over dotfiles: vd
* Neo keyboard layout
* Vim and keybindings
 * toggle ; at end of line
* quickly edit dotfiles with vim: vv
* fzf for editing dotfiles
* git alias: g
* zsh bell after every command
* v for fzf+vim in current git repo
* Tiling Window Manager keybindings
* NixOS
* Dark and Light color scheme switching
* Tools
 * tig
 * fzf
 * redshift
 * unclutter
 * zeal

* Scala
 * reverse compilation errors
