set nocompatible

" define a group `vimrc` and initialize.
augroup vimrc
    autocmd!
augroup END

source $HOME/.zgen/dottr/dottr-master/pan.vim
Fry edit-multiple-files

source $HOME/.vimrc_plugins
source $HOME/.vimrc_custom
source $HOME/.vimrc_statusline
source $HOME/.vimrc_keybindings


" Enable file type detection.
filetype plugin indent on


" Colorscheme
set termguicolors " true color support
syntax enable
if filereadable($HOME."/.theme") && match(readfile($HOME."/.theme"),"light")
    set background=dark
    colorscheme gruvbox
else
    set background=light
    colorscheme goodmorning
endif


" gui settings
set mouse=a
if has("gui_running")
    set guioptions=aci        " hide toolbars
    set guifont=Inconsolata\ 8
    "set lines=24 columns=80 " Maximize window.
    set guicursor+=a:blinkon0 "disable blinking
    set guicursor+=i-ci:block-iCursor-blinkon0 "insert mode: block, no blinking, highlight with iCursor
endif

" display
set cursorline                    " highlight current line
set number                        " enable line numbers
" set relativenumber                " show relative numbers for all lines but the current one
set ruler                         " show the cursor position all the time
set inccommand=nosplit            " live substitution preview
set ignorecase                    " smart case sensitive search
set smartcase                     "              "
set hls                           " hightlight search results
set scrolloff=5 sidescrolloff=10  " keep some lines before and after the cursor visible
set sidescroll=1                  " used when wrap is off
set wrap                          " break long lines
set linebreak                     " break only at word boundary
set listchars=tab:⊳\ ,trail:·     " display whitespaces
set list
set breakindent                   " indent wrapped lines
set breakindentopt=shift:2
set display=lastline,uhex         " if last line does not fit on screen, display it anyways

" editing
set gdefault                      " substitute all occurrences in line per default
set backspace=indent,eol,start    " allow backspacing over everything in insert mode
set tabstop=4                     " size of a hard tabstop
set shiftwidth=4                  " size of an "indent"
set softtabstop=4                 " a combination of spaces and tabs are used to simulate tab stops at a width
set smarttab                      " make "tab" insert indents instead of tabs at the beginning of a line
set expandtab                     " always uses spaces instead of tab characters
set virtualedit=block,onemore
set nostartofline                 " keep column position when switching buffers

" behavior
set hidden                        " switch from unsaved buffers
set shell=zsh
set encoding=utf-8
set history=10000                 " keep x lines of command line history
set showcmd                       " display incomplete commands
set wildmenu                      " better command line completion
set wildmode=list:longest,full
set lazyredraw                    " performance: dont redraw while executing macros
set autoread                      " read file when changed from outside
set confirm                       " ask to save files when closing vim
" set exrc                          " source .vimrc from directories
" set secure                        " secure local vimrc execution
set wildignore=*.o,*.obj,*.class,target/**
set viewoptions=cursor,folds,slash,unix
set clipboard=unnamedplus

" backup/undo/swap files
set swapfile
set backup
set undofile

set undodir=~/.vim/tmp/undo//     " undo files
set backupdir=~/.vim/tmp/backup// " backups
set directory=~/.vim/tmp/swap//   " swap files

" Make those folders automatically if they don't already exist.
if !isdirectory(expand(&undodir))
    call mkdir(expand(&undodir), "p")
endif
if !isdirectory(expand(&backupdir))
    call mkdir(expand(&backupdir), "p")
endif
if !isdirectory(expand(&directory))
    call mkdir(expand(&directory), "p")
endif

" change directory to the current buffer when opening files.
" set autochdir
autocmd vimrc BufEnter * set noreadonly " no delay, when editing read-only files
autocmd vimrc BufEnter * silent! lcd %:p:h

" break text automatically
autocmd vimrc FileType text setlocal textwidth=78

let g:tex_flavor = "latex"

" set spell spelllang=en_us

autocmd Filetype scala setlocal expandtab tabstop=2 shiftwidth=2 softtabstop=2

" filetype aliases
autocmd vimrc BufNewFile,BufRead *.sbt set filetype=scala
autocmd vimrc BufNewFile,BufRead *.gdb set filetype=sh
autocmd vimrc BufNewFile,BufRead *.jad set filetype=java

" on save, autoformat - also removes trailing spaces
" au BufWritePre * call AutoformatFixedUndo()

function! AutoformatFixedUndo()
    " inspired by http://vim.wikia.com/wiki/Restore_the_cursor_position_after_undoing_text_change_made_by_a_script
    " "_x deletes char without putting x into the yank register
    :normal ix
    :normal "_x
    :Autoformat
    :undojoin
endfunction


" return to last edit position when opening a file.
autocmd vimrc BufReadPost *
\ if line("'\"") > 0 && line("'\"") <= line("$") |
\   if &filetype == 'gitcommit' |
\       setlocal spell |
\   else |
\      exe "normal! g`\"" |
\    endif |
\ endif


if has('nvim')
    " neovim: automatically close terminal when process exited
    autocmd TermClose * call feedkeys('<cr>')
endif

" leave insert mode quickly
if ! has('gui_running')
    set ttimeoutlen=10
    augroup FastEscape
        autocmd!
    augroup END

    autocmd FastEscape InsertEnter * set timeoutlen=0
    autocmd FastEscape InsertLeave * set timeoutlen=1000
endif

