set nocompatible " Use Vim settings, rather than Vi settings

filetype off                  " required by Vundle
set rtp+=~/.vim/bundle/vundle/
call vundle#rc()

" let Vundle manage Vundle
Bundle 'gmarik/vundle'

Bundle "Shougo/vimproc"
"Bundle "Shougo/vimshell"


" statusline
Bundle 'itchyny/lightline.vim'
set laststatus=2
let g:lightline = {
    \ 'colorscheme': 'jellybeans',
    \ 'active': {
    \   'left': [ [ 'mode' ],
    \             [ 'fugitive', 'readonly', 'filename'] ]
    \ },
    \ 'component_function': {
    \   'fugitive': 'MyFugitive',
    \   'modified': 'MyModified',
    \   'filename': 'MyFilename',
    \   'readonly': 'MyReadonly',
    \ },
    \ 'separator': { 'left': '', 'right': '' },
    \ 'subseparator': { 'left': '|', 'right': '|' }
    \ }

function! MyModified()
    return &ft =~ 'help' ? '' : &modified ? '+' : &modifiable ? '' : '-'
endfunction

function! MyReadonly()
    return &ft !~? 'help' && &readonly ? 'RO' : ''
endfunction

function! MyFugitive()
    if !exists('*fugitive#head')
        return ''
    endif
    return fugitive#head()
endfunction

function! MyFilename()
  let fname = expand('%')
  return fname == '__Tagbar__' ? g:lightline.fname :
        \ fname =~ '__Gundo\|NERD_tree' ? '' :
        \ &ft == 'unite' ? unite#get_status_string() :
        \ &ft == 'vimshell' ? vimshell#get_status_string() :
        \ ('' != fname ? fname : '[No Name]') .
        \ ('' != MyGitModified() ? ' ' . MyGitModified() : '') .
        \ ('' != MyModified() ? ' ' . MyModified() : '')
"        \ ('' != MyReadonly() ? MyReadonly() . ' ' : '') .
endfunction

function! MyGitModified()
    if !exists('b:git_modified')
        let b:git_modified = ''
    endif
    return b:git_modified
endfunction

function! UpdateGitModified()
    if !exists('*fugitive#head')
        return
    endif
    let full_path = expand('%:p')
    let git_dir = fugitive#extract_git_dir(full_path)
    let work_dir = fnamemodify(git_dir, ':h')
    let status = system("git --git-dir=" . shellescape(git_dir) . " --work-tree="
                \ . shellescape(work_dir) . " status --porcelain "
                \ . shellescape(full_path))
    if status == ''
        let b:git_modified = ''
    else
        let b:git_modified = split(status)[0]
    endif
endfunction

augroup git_modified
    autocmd!
    autocmd BufWritePost * call UpdateGitModified()
    autocmd WinEnter * call UpdateGitModified()
    autocmd WinLeave * call UpdateGitModified()
augroup END

augroup misc
    autocmd!
    autocmd BufReadPost *    " Return to last edit position when opening a file (I want this!)
    \ if line("'\"") > 0 && line("'\"") <= line("$") |
    \   exe "normal! g`\"" |
    \ endif

    autocmd BufEnter *.hh,*.cc,*.h,*.cpp let g:formatprg_args_expr_cpp = '"--mode=c"'

    " apply autoformat and delete trailing empty line
    autocmd BufWritePost *.hh,*.cc,*.h,*.cpp
    \ exec 'Autoformat' |
    \ call TrimEmptyLines()
augroup END

function! TrimEmptyLines()
    let save_cursor = getpos(".")
    :silent! %s#\($\n\s*\)\+\%$##
    call setpos('.', save_cursor)
endfunction

let g:tagbar_status_func = 'TagbarStatusFunc'

function! TagbarStatusFunc(current, sort, fname, ...) abort
    let g:lightline.fname = a:fname
  return lightline#statusline(0)
endfunction




" rainbow parentheses
Bundle 'oblitum/rainbow'
"au FileType c,cpp,objc,objcpp call rainbow#load()
let g:rainbow_active = 1

" show 'Match x of y' when searching
Bundle 'henrik/vim-indexed-search'

" file browser
Bundle 'scrooloose/nerdtree'
nnoremap <silent> <F2> :NERDTreeToggle<CR>

" fuzzy autocompletion
Bundle 'Valloric/YouCompleteMe'
let g:ycm_autoclose_preview_window_after_insertion = 1
let g:EclimCompletionMethod = 'omnifunc'
"let g:ycm_filetype_whitelist = { 'scala': 1 }

" commenting
Bundle 'scrooloose/nerdcommenter'

"automatically-close-brackets-magic
Bundle 'Raimondi/delimitMate'

" git support
Bundle 'tpope/vim-fugitive'
Bundle 'gregsexton/gitv'
Bundle 'tpope/vim-git'
"Bundle 'airblade/vim-gitgutter'

" Collaborative Editing
"Bundle 'FredKSchott/CoVim'

"color highlighting for CSS
Bundle 'ap/vim-css-color'

"markdown filetype and syntax
Bundle 'tpope/vim-markdown'

" Colorscheme
Bundle 'godlygeek/csapprox'
"Bundle "nanotech/jellybeans.vim"
"Bundle 'chriskempson/base16-vim'
Bundle 'chriskempson/tomorrow-theme', {'rtp': 'vim/'}
"set background=dark
if filereadable($HOME."/.colors") && match(readfile($HOME."/.colors"),"light")
    colorscheme Tomorrow-Night-Bright
else
    colorscheme Tomorrow
endif

"map <F3> :colorscheme Tomorrow-Night-Bright<CR>
"map <F4> :colorscheme Tomorrow<CR>
"set term=ansi
syntax on
"set t_Co=256




let mapleader=","
let g:mapleader=","

" Switch buffers with tab
nnoremap <Tab> :bnext<CR>
nnoremap <S-Tab> :bprevious<CR>

" Smart way to move between windows, adjusted for neo!
" in insert mode
imap ∫ <C-o><C-W>h
imap ∀ <C-o><C-W>j
imap Λ <C-o><C-W>k
imap ∃ <C-o><C-W>l
" and in other modes
map ∫ <C-W>h
map ∀ <C-W>j
map Λ <C-W>k
map ∃ <C-W>l

" Smart way to move between tabs - in NEO! :D
" in insert mode
imap √ <C-o>:tabprev<cr>
imap ℂ <C-o>:tabnext<cr>
" in other modes
map √ :tabprev<cr>
map ℂ :tabnext<cr>

" save files as root
cmap w!! w !sudo tee % >/dev/null

set mouse=a
if has("gui_running")
  set guioptions=aci        " hide toolbars
  set guifont=Inconsolata\ 13
  set lines=24 columns=80 " Maximize window.
endif



" display
set cursorline                    " highlight current line
set number                        " enable line numbers
set ruler                         " show the cursor position all the time
set incsearch                     " do incremental searching
set ignorecase                    " smart case sensitive search
set smartcase                     "              "
set hls                           " hightlight search results
nnoremap <c-n> :nohlsearch<CR>
set list
set listchars=tab:⊳\ ,trail:·     " display whitespaces
set scrolloff=10 sidescrolloff=10 " keep some lines before and after the cursor visible

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
  autocmd FileType make setlocal ts=8 sts=8 sw=8 noexpandtab
  autocmd FileType scala setlocal ts=2 sts=2 sw=2 expandtab

  " filetype aliases
  au BufNewFile,BufRead *.sbt set filetype=scala

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


