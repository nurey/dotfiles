" Vincent Foley Bourgon's .vimrc (gnuvince@yahoo.ca)
" Last change: 2001/07/09

" allow to copy to OS X clipboard
set clipboard=unnamed

" No compatible.  You want to use Vim, not vi
set nocp

" Use a history file
set viminfo='10,\"100,:20,%,n~/.viminfo

" We don't wrap lines, they become a LONG horizontal one (useful)
set nowrap

" Set background to dark to have nicer syntax highlighting.
set background=dark

" We keep 3 lines when scrolling
set scrolloff=3

" We show vertical and horizontal position
set ruler

" Y = y$ not yy.  More intuative
noremap Y y$

" Tilde (~) acts like an operator (� la 'd' or 'c')
set top

" Incremental search
set is

" Ignore case when searching
set ic

" Highlight search
set hlsearch

set smartcase                   " Do smart case search

" Show matching ()'s []'s {}'s
set sm

" Autoindents
set ai

" Autoindents C code
set cin

" Tabs are 4 spaces long
set tabstop=2

set smarttab            " Tab in front of line uses shiftwidth - good for coding

" When autoindent does a tab, it's 4 spaces long
set shiftwidth=2

" No need to save to make a :next :previous, etc.
set aw

" C-a and C-e go to beginning/end of line in insert mode (I hate Home and End)
inoremap <C-a> <Home>
inoremap <C-e> <End>

" I like using C-g � la Emacs in the command line.  Don't ask me why.
cnoremap <C-g> <Esc>

" No idea what it's for...
set backspace=2

" No bell sound
set noerrorbells

" Put title in title bar
set title

" Smoother changes
set ttyfast

" Tabs are converted to space characters
set et

set wildmenu            " Enhanced command line completion
set smartindent     " this is pretty nifty most of the time

" Remove autocommands just in case
autocmd!

" When using mutt or slrn, text width=72
autocmd BufRead  mutt*[0-9]                    set tw=72
autocmd BufRead  .followup,.article,.letter    set tw=72

" Text files have a text width of 72 characters
autocmd BufNewFile *.txt                       set tw=72
autocmd BufRead    *.txt                       set tw=72

" LaTeX configuration is in ~/vim/vim.latex
autocmd BufNewFile *.tex            source ~/vim/latex.vimrc
autocmd BufRead    *.tex            source ~/vim/latex.vimrc

" Automatically chmod +x Shell and Perl scripts
"autocmd BufWritePost   *.sh             !chmod +x %
"autocmd BufWritePost   *.pl             !chmod +x %

" Also, support editing of gzip-compressed files. DO NOT REMOVE THIS!
" This is also used when loading the compressed helpfiles.
augroup gzip
  " Remove all gzip autocommands
  au!

  " Enable editing of gzipped files
  "       read: set binary mode before reading the file
  "             uncompress text in buffer after reading
  "      write: compress file after writing
  "     append: uncompress file, append, compress file
  autocmd BufReadPre,FileReadPre        *.gz set bin
  autocmd BufReadPre,FileReadPre        *.gz let ch_save = &ch|set ch=2
  autocmd BufReadPost,FileReadPost      *.gz '[,']!gunzip
  autocmd BufReadPost,FileReadPost      *.gz set nobin
  autocmd BufReadPost,FileReadPost      *.gz let &ch = ch_save|unlet ch_save
  autocmd BufReadPost,FileReadPost      *.gz execute ":doautocmd BufReadPost " . expand("%:r")

  autocmd BufWritePost,FileWritePost    *.gz !mv <afile> <afile>:r
  autocmd BufWritePost,FileWritePost    *.gz !gzip <afile>:r

  autocmd FileAppendPre                 *.gz !gunzip <afile>
  autocmd FileAppendPre                 *.gz !mv <afile>:r <afile>
  autocmd FileAppendPost                *.gz !mv <afile> <afile>:r
  autocmd FileAppendPost                *.gz !gzip <afile>:r
augroup END

augroup bzip2
  " Remove all bzip2 autocommands
  au!

  " Enable editing of bzipped files
  "       read: set binary mode before reading the file
  "             uncompress text in buffer after reading
  "      write: compress file after writing
  "     append: uncompress file, append, compress file
  autocmd BufReadPre,FileReadPre        *.bz2 set bin
  autocmd BufReadPre,FileReadPre        *.bz2 let ch_save = &ch|set ch=2
  autocmd BufReadPost,FileReadPost      *.bz2 |'[,']!bunzip2
  autocmd BufReadPost,FileReadPost      *.bz2 let &ch = ch_save|unlet ch_save
  autocmd BufReadPost,FileReadPost      *.bz2 execute ":doautocmd BufReadPost " . expand("%:r")

  autocmd BufWritePost,FileWritePost    *.bz2 !mv <afile> <afile>:r
  autocmd BufWritePost,FileWritePost    *.bz2 !bzip2 <afile>:r

  autocmd FileAppendPre                 *.bz2 !bunzip2 <afile>
  autocmd FileAppendPre                 *.bz2 !mv <afile>:r <afile>
  autocmd FileAppendPost                *.bz2 !mv <afile> <afile>:r
  autocmd FileAppendPost                *.bz2 !bzip2 -9 --repetitive-best <afile>:r
augroup END



" We put syntax highlighting (COLORS!!)
syntax on

"show tabs, spaces, end of lines
"set list
"set listchars=tab:>-,trail:.
set shell=bash

"inoremap ( ()<esc>:call BC_AddChar(")")<cr>i
"inoremap { {<cr>}<esc>:call BC_AddChar("}")<cr><esc>kA<cr>
"inoremap [ []<esc>:call BC_AddChar("]")<cr>i
"inoremap " ""<esc>:call BC_AddChar("\"")<cr>i
"" jump out of parenthesis
"inoremap <C-j> <esc>:call search(BC_GetChar(), "W")<cr>a
"
"function! BC_AddChar(schar)
"  if exists("b:robstack")
"    let b:robstack = b:robstack . a:schar
"  else
"    let b:robstack = a:schar
"  endif
"endfunction
"
"function! BC_GetChar()
"  let l:char = b:robstack[strlen(b:robstack)-1]
"  let b:robstack = strpart(b:robstack, 0, strlen(b:robstack)-1)
"  return l:char
"endfunction

"editing mapping (make cursor keys work like in windows. ie: <C-Left><C-Right>
"move to next word.
nnoremap <C-Left> b
vnoremap  <C-S-Left> b
nnoremap <C-S-Left> gh<C-O>b
inoremap <C-S-Left> <C-O>gh<C-O>b

nnoremap <C-Right> w
vnoremap  <C-S-Right> w
nnoremap <C-S-Right> gh<C-O>w
inoremap <C-S-Right> <C-O>gh<C-O>w

highlight Cursor   guifg=white  guibg=black
highlight iCursor  guifg=white  guibg=steelblue
set guicursor=n-v-c:block-Cursor
set guicursor+=i:ver100-iCursor
set guicursor+=n-v-c:blinkon0-Cursor
set guicursor+=i:blinkwait20-iCursor

if exists('+colorcolumn')
  set colorcolumn=80
else
  au BufWinEnter * let w:m2=matchadd('ErrorMsg', '\%>80v.\+', -1)
endif

"execute pathogen#infect()
