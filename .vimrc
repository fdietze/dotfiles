set nocompatible " Use Vim settings, rather than Vi settings

filetype off                  " required! (by Vundle?)
set rtp+=~/.vim/bundle/vundle/
call vundle#rc()

" let Vundle manage Vundle
Bundle 'gmarik/vundle'

" Vimside
Bundle "megaannum/self"
Bundle "megaannum/forms" 
Bundle "Shougo/vimproc"
Bundle "Shougo/vimshell"
Bundle "aemoncannon/ensime"
Bundle "megaannum/vimside"

" Colorscheme
Bundle "nanotech/jellybeans.vim"
colorscheme jellybeans
set term=ansi
set t_Co=256
syntax on


let mapleader=","
let g:mapleader=","

set mouse=a
if has("gui_running")
  set guioptions=aci        " hide toolbars
  set guifont=Monospace\ 8
  set lines=24 columns=80 " Maximize window.
endif



" display
set cursorline                    " highlight current line
set number                        " enable line numbers
set ruler                         " show the cursor position all the time
set incsearch                     " do incremental searching
set ignorecase                    " smart case sensitive search
set smartcase                     "              "
set list
set listchars=tab:•·,trail:·      " display whitespaces
set scrolloff=10 sidescrolloff=10 " keep some lines before and after the cursor visible

" editing
set backspace=indent,eol,start    " allow backspacing over everything in insert mode
set tabstop=2                     " size of a hard tabstop
set shiftwidth=2                  " size of an "indent"
set softtabstop=2                 " a combination of spaces and tabs are used to simulate tab stops at a width
set smarttab                      " make "tab" insert indents instead of tabs at the beginning of a line
set expandtab                     " always uses spaces instead of tab characters

" behavior
set hidden                        " switch from unsaved buffers
set shell=zsh
set nobackup                      " do not keep a backup file, use versions instead
set encoding=utf8
set history=1000                  " keep 50 lines of command line history
set showcmd                       " display incomplete commands
set wildmenu                      " better command line completion
set wildmode=list:longest,full
set lazyredraw                    " performance: dont redraw while executing macros
set autoread                      " read file when changed from outside





" Only do this part when compiled with support for autocommands.
if has("autocmd")

  " Enable file type detection.
  " Use the default filetype settings, so that mail gets 'tw' set to 72,
  " 'cindent' is on in C files, etc.
  " Also load indent files, to automatically do language-dependent indenting.
  filetype plugin indent on

  " Put these in an autocmd group, so that we can delete them easily.
  augroup vimrcEx
  au!

  " For all text files set 'textwidth' to 78 characters.
  autocmd FileType text setlocal textwidth=78

  " When editing a file, always jump to the last known cursor position.
  " Don't do it when the position is invalid or when inside an event handler
  " (happens when dropping a file on gvim).
  " Also don't do it when the mark is in the first line, that is the default
  " position when opening a file.
  autocmd BufReadPost *
    \ if line("'\"") > 1 && line("'\"") <= line("$") |
    \   exe "normal! g`\"" |
    \ endif

  augroup END

else

  set autoindent " always set autoindenting on

endif " has("autocmd")


