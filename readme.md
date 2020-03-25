
```bash
# install: zsh, yeganesh or dmenu, termite, xcwd, unclutter-xfixes, redshift, cope
# for panel: conky-cli with lua (lua-filesystem), ttf-droid
mkdir -p ~/projects
git clone --bare https://github.com/fdietze/dotfiles.git projects/dotfiles
GIT_DIR=$HOME/projects/dotfiles GIT_WORK_TREE=$HOME git checkout master

git clone https://github.com/tarjoilija/zgen.git "${HOME}/.zgen"
chsh -s /bin/zsh

ln -sf $HOME/.vim $HOME/.config/nvim
ln -sf $HOME/.vimrc $HOME/.vim/init.vim
vim +PlugInstall

ssh-keygen -t ed25519
```
