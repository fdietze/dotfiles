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


set mouse=a
if has("gui_running")
  set guioptions=aci        " hide toolbars
  set guifont=Inconsolata\ 15
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
set ttyfast

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
"set clipboard=unnamedplus         " alias unnamed register to the + register, which is the X Window clipboard
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


" fuzzy autocompletion, eclim
"Bundle 'Valloric/YouCompleteMe'
let g:ycm_auto_trigger = 0
let g:ycm_autoclose_preview_window_after_insertion = 1
let g:EclimCompletionMethod = 'omnifunc'
let g:EclimScalaSearchSingleResult = 'edit'
":set completeopt=longest,menuone
    
" select items with ENTER
":inoremap <expr> <CR> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"

" Some convenient mappings
" inoremap <expr> <Esc>      pumvisible() ? "\<C-e>" : "\<Esc>"
" inoremap <expr> <CR>       pumvisible() ? "\<C-y>" : "\<CR>"
" inoremap <expr> <Down>     pumvisible() ? "\<C-n>" : "\<Down>"
" inoremap <expr> <Up>       pumvisible() ? "\<C-p>" : "\<Up>"
" inoremap <expr> <C-d>      pumvisible() ? "\<PageDown>\<C-p>\<C-n>" : "\<C-d>"
" inoremap <expr> <C-u>      pumvisible() ? "\<PageUp>\<C-p>\<C-n>" : "\<C-u>"

" TODO: noninvasive completion
" <ESC> takes you out of insert mode
" inoremap <expr> <Esc>   pumvisible() ? "\<C-y>\<Esc>" : "\<Esc>"
" " <CR> accepts first, then sends the <CR>
" inoremap <expr> <CR>    pumvisible() ? "\<C-y>\<CR>" : "\<CR>"
" " <Down> and <Up> cycle like <Tab> and <S-Tab>
" inoremap <expr> <Down>  pumvisible() ? "\<C-n>" : "\<Down>"
" inoremap <expr> <Up>    pumvisible() ? "\<C-p>" : "\<Up>"
" " Jump up and down the list
" inoremap <expr> <C-d>   pumvisible() ? "\<PageDown>\<C-p>\<C-n>" : "\<C-d>"
" inoremap <expr> <C-u>   pumvisible() ? "\<PageUp>\<C-p>\<C-n>" : "\<C-u>"
" Automatically open and close the popup menu / preview window
" au CursorMovedI,InsertLeave * if pumvisible() == 0|silent! pclose|endif
" set completeopt=menu,preview,longest


"let g:ycm_filetype_whitelist = { 'scala': 1 }


" Colorscheme
"Bundle 'godlygeek/csapprox'
"Bundle 'vim-scripts/guicolorscheme.vim'
" Bundle 'nanotech/jellybeans.vim'
"Bundle 'chriskempson/base16-vim'
Bundle 'chriskempson/tomorrow-theme', {'rtp': 'vim/'}
"Bundle 'fdietze/goodday.vim'
"Bundle 'gerw/vim-HiLinkTrace'
"set background=dark
if filereadable($HOME."/.colors") && match(readfile($HOME."/.colors"),"light")
    colorscheme lucius
else
    colorscheme goodmorning
endif

"map <F3> :colorscheme Tomorrow-Night-Bright<CR>
"map <F4> :colorscheme Tomorrow<CR>
"set term=ansi
syntax on
"set t_Co=256

" leave insert mode quickly
if ! has('gui_running')
set ttimeoutlen=10
augroup FastEscape
  autocmd!
  au InsertEnter * set timeoutlen=0
  au InsertLeave * set timeoutlen=1000
augroup END
endif



" highlight current word by when pressing h
let g:highlighting = 0
function! Highlighting()
  if g:highlighting == 1 && @/ =~ '^\\<'.expand('<cword>').'\\>$'
    let g:highlighting = 0
    return ":silent nohlsearch\<CR>"
  endif
  let @/ = '\<'.expand('<cword>').'\>'
  let g:highlighting = 1
  return ":silent set hlsearch\<CR>"
endfunction
nnoremap <silent> <expr> h Highlighting()

" highlight visually selected text by pressing h
set guioptions+=a
function! MakePattern(text)
  let pat = escape(a:text, '\')
  let pat = substitute(pat, '\_s\+$', '\\s\\*', '')
  let pat = substitute(pat, '^\_s\+', '\\s\\*', '')
  let pat = substitute(pat, '\_s\+',  '\\_s\\+', 'g')
  return '\\V' . escape(pat, '\"')
endfunction
vnoremap <silent> h :<C-U>let @/="<C-R>=MakePattern(@*)<CR>"<CR>:set hls<CR>

" Highlight all instances of word under cursor, when idle.
" Useful when studying strange source code.
" Type <Leader>h to toggle highlighting on/off.
nnoremap <Leader>h :if AutoHighlightToggle()<Bar>set hls<Bar>endif<CR>
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
    augroup end
    setl updatetime=500
    echo 'Highlight current word: ON'
    return 1
  endif
endfunction


" Enable file type detection.
" Use the default filetype settings, so that mail gets 'tw' set to 72,
" 'cindent' is on in C files, etc.
" Also load indent files, to automatically do language-dependent indenting.
filetype plugin indent on

augroup misc
  autocmd!

  autocmd BufEnter *.hh,*.cc,*.h,*.cpp let g:formatprg_args_expr_cpp = '"--mode=c"'

  " apply autoformat and delete trailing empty line
  autocmd BufWritePost *.hh,*.cc,*.h,*.cpp,*.scala,*.sh
              \ call TrimEmptyLines()
augroup END

function! TrimEmptyLines()
  let save_cursor = getpos(".")
  :silent! %s#\($\n\s*\)\+\%$##
  call setpos('.', save_cursor)
endfunction


" Put these in an autocmd group, so that we can delete them easily.
augroup vimrcEx
au!

" For all text files set 'textwidth' to 78 characters.
autocmd FileType text setlocal textwidth=78
autocmd FileType make setlocal ts=8 sts=8 sw=8 noexpandtab
autocmd FileType scala setlocal ts=2 sts=2 sw=2 expandtab

" filetype aliases
au BufNewFile,BufRead *.sbt set filetype=scala

augroup END

