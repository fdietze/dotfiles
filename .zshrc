# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi


export DISABLE_MAGIC_FUNCTIONS=true # fix slow paste in zsh (https://github.com/vercel/hyper/issues/1276#issuecomment-510829201)


# load zgenom plugin manager (https://github.com/jandamm/zgenom)
source "${HOME}/.zgenom/zgenom.zsh"
if ! zgenom saved; then
    echo "Creating a zgenom save"

    # completions
    zgenom load zsh-users/zsh-completions

    # theme & colors
    zgenom load romkatv/powerlevel10k powerlevel10k
    zgenom load joel-porquet/zsh-dircolors-solarized.git

    # plugins
    zgenom load zsh-users/zsh-autosuggestions
    zgenom load zsh-users/zsh-syntax-highlighting # order is important (https://github.com/zsh-users/zsh-syntax-highlighting#why-must-zsh-syntax-highlightingzsh-be-sourced-at-the-end-of-the-zshrc-file)
    zgenom load jeffreytse/zsh-vi-mode
    zgenom load dottr/dottr # zsh snippets (https://github.com/dottr/dottr/)
    zgenom load rupa/z # jump to most used directories

    # save all to init script
    zgenom save

    # Compile your zsh files
    zgenom compile "$HOME/.zshrc"
fi


# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh


source ~/.sh_aliases

# fix fzf with zsh-vi-mode
# https://github.com/jeffreytse/zsh-vi-mode/issues/4#issuecomment-757234569
zvm_after_init_commands+=('source ~/.zshrc.fzf')



# load dottr snippets
fry bell-on-precmd # produces output, which p10k will warn about
# fry completion
# fry ncserve
# fry alias-usage-analysis
fry print-expanded-alias
# # fry vim-open-files-at-lines
fry search-select-edit
fry git-select-commit
# fry git-onstage
# fry interactive-mv
fry cd-tmp
fry cd-git-root
# fry mkdir-cd
# fry screencapture
# fry transcode-video
# fry bind2maps
# fry git-dirty-files-command
# fry watchdo
fry nvim-rpc # to switch color schemes

eval "$(direnv hook zsh)" # load environment vars depending on directory https://direnv.net/docs/hook.html#zsh


[[ ! -f "/etc/grc.zsh" ]] || source /etc/grc.zsh # colors outputs of commands (https://github.com/garabik/grc)


setopt nonomatch # avoid the zsh "no matches found" / allows sbt ~compile


export HISTSIZE=10000000
export SAVEHIST=10000000


# additional keybindings, compatible with zsh_vi_mode ()
function zvm_before_init() {
  # history prefix search
  zvm_bindkey viins '^[[A' history-beginning-search-backward
  zvm_bindkey viins '^[[B' history-beginning-search-forward
  zvm_bindkey vicmd '^[[A' history-beginning-search-backward
  zvm_bindkey vicmd '^[[B' history-beginning-search-forward

  # fix home/end keys
  # https://github.com/jeffreytse/zsh-vi-mode/pull/138
  zvm_bindkey viins '^[[H'  beginning-of-line
  zvm_bindkey vicmd '^[[H'  beginning-of-line
  zvm_bindkey viins '^[[F'  end-of-line
  zvm_bindkey vicmd '^[[F'  end-of-line
}
