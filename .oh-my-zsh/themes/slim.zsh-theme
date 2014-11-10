# http://www.paradox.io/posts/9-my-new-zsh-prompt
# https://coderwall.com/p/kmchbw

function preexec() {
  timer=${timer:-$SECONDS}
}


function precmd() {
  if [ $timer ]; then
    timer_show=$(($SECONDS - $timer))
    if [ $timer_show -ge 3 ]; then
        PROMPT_TIMER=" %{$fg[cyan]%}${timer_show}s %{$reset_color%}
"
    else
        PROMPT_TIMER=''
    fi
    unset timer
  fi
}

PROMPT_EXIT_STATUS="%(?,, exit status %{${fg_bold[red]}%}%?%{$reset_color%}
)"
PROMPT_DIR="%{$fg_bold[blue]%}%(2~,%c,)%{$reset_color%}"
PROMPT_PWD="%{$fg[blue]%}%~%{$reset_color%}"
PROMPT_SYMBOL="%{$fg_bold[blue]%}%(!,#,\$)%{$reset_color%}"

PROMPT='$PROMPT_EXIT_STATUS$PROMPT_TIMER$PROMPT_DIR$(git_prompt_info)$PROMPT_SYMBOL '

RPROMPT='$PROMPT_PWD'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[blue]%}[%{$fg_bold[magenta]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$reset_color%}%{$fg[cyan]%}*%{$reset_color%}%{$fg[blue]%}]"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$reset_color%}%{$fg[blue]%}]"

# remove space at the right
# ZLE_RPROMPT_INDENT=0
