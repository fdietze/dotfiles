if status is-interactive
    # Commands to run in interactive sessions can go here

    # https://superuser.com/questions/446925/re-use-profile-for-fish/447777#447777
    fish_add_path $HOME/bin
    fish_add_path $HOME/.local/bin # pip
    fish_add_path $HOME/local/bin
    fish_add_path $HOME/.npm-packages/bin
    fish_add_path $HOME/.cargo/bin
    fish_add_path $HOME/go/bin
    fish_add_path $HOME/development/flutter/bin
    fish_add_path $HOME/.local/share/coursier/bin


    set -gx EDITOR nvim


    # fzf
    set -gx FZF_DEFAULT_COMMAND 'rg --files --hidden --glob "!.git"'
    set -gx FZF_DEFAULT_OPTS "--extended --multi --ansi --exit-0" # extended match and multiple selections
    set -gx FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"
    set -gx FZF_CTRL_T_OPTS "--tac --height 90% --reverse --preview 'pistol {} \$FZF_PREVIEW_COLUMNS \$FZF_PREVIEW_LINES' --bind 'ctrl-d:preview-page-down,ctrl-r:reload($FZF_CTRL_T_COMMAND)"

    # direnv
    direnv hook fish | source


    # Emulates vim's cursor shape behavior
    # https://fishshell.com/docs/current/interactive.html#vi-mode-commands
    # Set the normal and visual mode cursors to a block
    set fish_cursor_default block
    # Set the insert mode cursor to a line
    set fish_cursor_insert line
    # Set the replace mode cursor to an underscore
    set fish_cursor_replace_one underscore
    # The following variable can be used to configure cursor shape in
    # visual mode, but due to fish_cursor_default, is redundant here
    set fish_cursor_visual block


    

    # load environment variables

    # load aliases
    # TODO: https://superuser.com/questions/1049368/add-abbreviations-in-fish-config/1688606#1688606
    source (sed 's|alias \(\w\w*\)=\(.*\)|abbr -a \1 \2|' ~/.aliases | psub)
end
