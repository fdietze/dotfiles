" TODO: exit insert mode on <Up>/<Down>, move inside wrapped lines
" TODO: leave insert mode when losing focus?
" TODO: remove stuff, thats already in vim-sensible
" http://chibicode.com/vimrc/
" http://nvie.com/posts/how-i-boosted-my-vim/


" Use Vim settings, rather than Vi settings
set nocompatible

" allow UTF-8 characters in vimrc
scriptencoding utf-8

" clear all keymappings
mapclear


source $HOME/.vimrc_plugins
source $HOME/.vimrc_custom
source $HOME/.vimrc_statusline
source $HOME/.vimrc_keybindings


" Enable file type detection.
filetype plugin indent on


" Colorscheme
syntax enable
if filereadable($HOME."/.colors") && match(readfile($HOME."/.colors"),"light")
    set background=dark
    colorscheme solarized
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
    set guicursor+=a:blinkon0 "disible blinking
    set guicursor+=i-ci:block-iCursor-blinkon0 "insert mode: block, no blinking, highlight with iCursor
endif

" display
set cursorline                    " highlight current line
set number                        " enable line numbers
set relativenumber                " show relative numbers for all lines but the current one
set ruler                         " show the cursor position all the time
set incsearch                     " do incremental searching
set ignorecase                    " smart case sensitive search
set smartcase                     "              "
set hls                           " hightlight search results
set scrolloff=5 sidescrolloff=10  " keep some lines before and after the cursor visible
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
set shell=/bin/bash
set encoding=utf-8
set history=1000                  " keep x lines of command line history
set showcmd                       " display incomplete commands
set wildmenu                      " better command line completion
set wildmode=list:longest,full
set lazyredraw                    " performance: dont redraw while executing macros
set ttyfast                       " allow vim to write more characters to screen
set autoread                      " read file when changed from outside
set confirm                       " ask to save files when closing vim
set exrc                          " source .vimrc from directories
set secure                        " secure local vimrc execution
set wildignore=*.o,*.obj,*.class,target/**
set viewoptions=cursor,folds,slash,unix

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

" define a group `vimrc` and initialize.
augroup vimrc
    autocmd!
augroup END

" change directory to the current buffer when opening files.
" set autochdir
autocmd vimrc BufEnter * silent! lcd %:p:h

" break text automatically
autocmd vimrc FileType text setlocal textwidth=78

" filetype aliases
autocmd vimrc BufNewFile,BufRead *.sbt set filetype=scala
autocmd vimrc BufNewFile,BufRead *.gdb set filetype=sh
autocmd vimrc BufNewFile,BufRead *.jad set filetype=java

" on save, delete trailing spaces
autocmd vimrc FileType vim,html,css,scss,javascript,sh
            \ autocmd BufWritePre * call StripTrailingSpaces()

" on save, autoformat
autocmd vimrc FileType vim,html
            \ autocmd BufWritePre *.vim *.html Autoformat

" return to last edit position when opening a file.
" except for git commits: Enter insert mode instead.
autocmd vimrc BufReadPost *
            \ if line("'\"") > 0 && line("'\"") <= line("$") |
            \   if &filetype == 'gitcommit' |
            \       setlocal spell |
            \       startinsert |
            \   else |
            \      exe "normal! g`\"" |
            \    endif |
            \ endif


" leave insert mode quickly
if ! has('gui_running')
    set ttimeoutlen=10
    augroup FastEscape
        autocmd!
    augroup END

    autocmd FastEscape InsertEnter * set timeoutlen=0
    autocmd FastEscape InsertLeave * set timeoutlen=1000
endif

" don't move cursor when leaving insert mode, breaks multiple-cursors
" let CursorColumnI = 0 "the cursor column position in INSERT
" autocmd InsertEnter * let CursorColumnI = col('.')
" autocmd CursorMovedI * let CursorColumnI = col('.')
" autocmd InsertLeave * if col('.') != CursorColumnI | call cursor(0, col('.')+1) | endif

