" TODO: exit insert mode on <Up>/<Down>, move inside wrapped lines
" TODO: leave insert mode when losing focus?
" TODO: remove stuff, thats already in vim-sensible
" TODO: j{a-z} jump to mark
" https://github.com/Shougo/unite.vim
" http://chibicode.com/vimrc/
" http://nvie.com/posts/how-i-boosted-my-vim/
" TODO: Plugin 'vim-scripts/ShowMarks'
" TODO: Plugin 'ervandew/supertab'
"TODO: Plugin 'scrooloose/syntastic'

set nocompatible " Use Vim settings, rather than Vi settings

filetype off                  " required by Vundle
set rtp+=~/.vim/bundle/vundle/
call vundle#rc()

" let Vundle manage Vundle
Plugin 'gmarik/vundle'

source $HOME/.vimrc_plugins
source $HOME/.vimrc_statusline
source $HOME/.vimrc_keybindings

" Enable file type detection.
filetype plugin indent on

" gui settings
set mouse=a
if has("gui_running")
  set guioptions=aci        " hide toolbars
  set guifont=Inconsolata\ 16
  "set lines=24 columns=80 " Maximize window.
  set guicursor+=a:blinkon0 "disible blinking
  set guicursor+=i-ci:block-iCursor-blinkon0 "insert mode: block, no blinking, highlight with iCursor
endif

" display
set cursorline                    " highlight current line
set number                        " enable line numbers
set ruler                         " show the cursor position all the time
set incsearch                     " do incremental searching
set ignorecase                    " smart case sensitive search
set smartcase                     "              "
set hls                           " hightlight search results
set list
set listchars=tab:⊳\ ,trail:·     " display whitespaces
set scrolloff=5 sidescrolloff=10  " keep some lines before and after the cursor visible
" set ttyfast

" editing
set backspace=indent,eol,start    " allow backspacing over everything in insert mode
set tabstop=4                     " size of a hard tabstop
set shiftwidth=4                  " size of an "indent"
set softtabstop=4                 " a combination of spaces and tabs are used to simulate tab stops at a width
set smarttab                      " make "tab" insert indents instead of tabs at the beginning of a line
set expandtab                     " always uses spaces instead of tab characters

" behavior
set hidden                        " switch from unsaved buffers
set shell=/bin/bash
set encoding=utf8
set history=1000                  " keep 50 lines of command line history
set showcmd                       " display incomplete commands
set wildmenu                      " better command line completion
set wildmode=list:longest,full
set lazyredraw                    " performance: dont redraw while executing macros
set autoread                      " read file when changed from outside
set confirm                       " ask to save files when closing vim
" set clipboard=unnamedplus         " alias unnamed register to the + register, which is the X Window clipboard
cd %:p:h                          " cd to directory of current file

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


" Colorscheme
"Bundle 'godlygeek/csapprox'
"Bundle 'vim-scripts/guicolorscheme.vim'
" Bundle 'nanotech/jellybeans.vim'
"Bundle 'chriskempson/base16-vim'
Bundle 'chriskempson/tomorrow-theme', {'rtp': 'vim/'}
"Bundle 'fdietze/goodday.vim'
"set background=dark
if filereadable($HOME."/.colors") && match(readfile($HOME."/.colors"),"light")
    set background=dark
    colorscheme base16-chalk
else
    set background=light
    colorscheme goodmorning
endif

syntax on
"set t_Co=256





" highlight current word
let g:highlighting = 0
function! HighlightCurrentWord()
    if g:highlighting == 1 && @/ =~ '^\\C\\<'.expand('<cword>').'\\>$'
        let g:highlighting = 0
        return ":silent nohlsearch\<CR>"
    endif
    let @/ = '\C\<'.expand('<cword>').'\>'
    let g:highlighting = 1
    return ":silent set hlsearch\<CR>"
endfunction

" highlight visually selected text
function! HighlightSelection()
  let pat = escape(@*, '\')
  let pat = substitute(pat, '\_s\+$', '\\s\\*', '')
  let pat = substitute(pat, '^\_s\+', '\\s\\*', '')
  let pat = substitute(pat, '\_s\+',  '\\_s\\+', 'g')
  let pat = "\\V" . escape(pat, '\"')
  let @/=pat
  let g:highlighting = 1
endfunction

" Highlight all instances of word under cursor when idle
function! AutoHighlightToggle()
    let @/ = ''
    if exists('#auto_highlight')
        au! auto_highlight
        augroup! auto_highlight
        setl updatetime=4000
        echo 'Highlight current word: off'
        return 0
    else
        augroup auto_highlight
            au!
            au CursorHold * let @/ = '\V\<'.escape(expand('<cword>'), '\').'\>'
        augroup END
        setl updatetime=200
        echo 'Highlight current word: ON'
        return 1
    endif
endfunction


function! StripTrailingSpaces()
    let _s=@/ " backup search string
    let save_cursor = getpos(".") " backup cursor
    " :silent! %s#\($\n\s*\)\+\%$##
    %s/\s\+$//e
    let @/=_s " restore search string
    call setpos('.', save_cursor) " restore cursor
endfunction


augroup misc
    autocmd!

    autocmd FileType text setlocal textwidth=78
    autocmd FileType make setlocal ts=8 sts=8 sw=8 noexpandtab

    " filetype aliases
    au BufNewFile,BufRead *.sbt set filetype=scala
    au BufNewFile,BufRead *.gdb set filetype=sh
    au BufNewFile,BufRead *.jad set filetype=java

    " apply autoformat and delete trailing empty line
    autocmd BufWritePost *.hh,*.cc,*.h,*.cpp,*.scala,*.sh,*.vimrc*
                \ call StripTrailingSpaces()

    autocmd BufEnter *.hh,*.cc,*.h,*.cpp let g:formatprg_args_expr_cpp = '"--mode=c"'
augroup END


" leave insert mode quickly
if ! has('gui_running')
    set ttimeoutlen=10
    augroup FastEscape
        autocmd!
        au InsertEnter * set timeoutlen=0
        au InsertLeave * set timeoutlen=1000
    augroup END
endif
