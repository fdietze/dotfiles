
```bash
mkdir -p ~/projects
git clone --bare https://github.com/fdietze/dotfiles.git projects/dotfiles
GIT_DIR=$HOME/projects/dotfiles GIT_WORK_TREE=$HOME git checkout master

git clone https://github.com/tarjoilija/zgen.git "${HOME}/.zgen"
```
