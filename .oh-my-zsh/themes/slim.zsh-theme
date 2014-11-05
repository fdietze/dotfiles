# http://www.paradox.io/posts/9-my-new-zsh-prompt
PROMPT='%{$fg_bold[blue]%}%(2~,%c,)%{$reset_color%}$(git_prompt_info)%{$fg_bold[blue]%}%(!,#,\$)%{$reset_color%} '

RPROMPT='%{$fg[blue]%}%~%(?,, %{${fg_bold[red]}%}%?)%{$reset_color%}'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[blue]%}[%{$fg_bold[magenta]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[green]%}*%{$reset_color%}%{$fg[blue]%}]"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$reset_color%}%{$fg[blue]%}]"

# remove space at the right
# ZLE_RPROMPT_INDENT=0
