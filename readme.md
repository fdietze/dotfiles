# How I use my computer


## My Installation
**WARNING**: These are the installation instructions for myself, not for you. You should have your own repository and get inspired by this one. If you have any questions, feel free to open issues.
```bash

# install:
# zsh, neovim, rg, fzf, diff-so-fancy, direnv, grc
# alacritty, xcwd, unclutter-xfixes, redshift

mkdir -p ~/projects
git clone --bare git@github.com:fdietze/dotfiles.git projects/dotfiles
alias dt="GIT_DIR=$HOME/projects/dotfiles GIT_WORK_TREE=$HOME git -c status.showUntrackedFiles=no"
dt checkout master


# ZSH plugin manager
git clone https://github.com/jandamm/zgenom.git "${HOME}/.zgenom"
chsh -s /bin/zsh # make zsh the default shell


# make vim/nvim config compatible
ln -sf $HOME/.vim $HOME/.config/nvim
ln -sf $HOME/.vimrc $HOME/.vim/init.vim
vim +PlugInstall


ssh-keygen -t ed25519
```

# Resources

* How to manage dotfiles with git: https://www.atlassian.com/git/tutorials/dotfiles
* What are `.zshrc` / `.zshenv` / `.zprofile`? https://unix.stackexchange.com/questions/71253/what-should-shouldnt-go-in-zshenv-zshrc-zlogin-zprofile-zlogout
* Better bash functions: https://cuddly-octo-palm-tree.com/posts/2021-10-31-better-bash-functions/

# Notes

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
