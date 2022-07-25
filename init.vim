" --------------------------
"  --- Encoding Setting ----
" --------------------------
set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8,ucs-boms,euc-jp,cp932
set termencoding=utf-8
scriptencoding utf-8

" ---- Disable Filetype for Read file settings
filetype off
filetype plugin indent off

" --------------------------
" ---- Install jetpack ----
" --------------------------
if has('vim_starting')
    let s:jetpackfile = expand('<sfile>:p:h') .. '/pack/jetpack/opt/vim-jetpack/plugin/jetpack.vim'
    let s:jetpackurl = "https://raw.githubusercontent.com/tani/vim-jetpack/master/plugin/jetpack.vim"
    if !filereadable(s:jetpackfile)
      call system(printf('curl -fsSLo %s --create-dirs %s', s:jetpackfile, s:jetpackurl))
    endif
endif

let s:jetpack_root = expand('$NVIM_HOME') . '/plugin'
let s:jetpack_vim = s:jetpack_root . '/jetpack.vim'

" -------------------------
" ---- Plugins Install ----
" -------------------------
packadd vim-jetpack
call jetpack#begin(expand('$NVIM_HOME') . '/plugin')
    Jetpack 'tani/vim-jetpack', {'opt': 1}
    Jetpack 'airblade/vim-gitgutter'
    Jetpack 'sbdchd/neoformat'
    Jetpack 'editorconfig/editorconfig-vim'
    Jetpack 'tyru/caw.vim' " comment out
    Jetpack 'mattn/vim-goimports', {'for': 'go'}
call jetpack#end()

" --------------------------------------
" ---- Plugin Dependencies Settings ----
" --------------------------------------
" if !has('python') && !has('pip')
"     call system('pip install --upgrade pip')
"     call system('pip install neovim --upgrade')
" endif
"
" if !has('python3') && !has('pip3')
"     call system('pip3 install --upgrade pip')
"     call system('pip3 install neovim --upgrade')
" endif

let g:python_host_skip_check = 1
let g:python2_host_skip_check = 1
let g:python3_host_skip_check = 1
"
if executable('python')
    let g:python_host_prog=system('which python')
endif

if executable('python3')
    let g:python3_host_prog=system('which python3')
endif

let g:jetpack#optimization = 1
for name in jetpack#names()
  if !jetpack#tap(name)
    call jetpack#sync()
    break
  endif
endfor

" ----------------------------
" ---- AutoGroup Settings ----
" ----------------------------
augroup AutoGroup
    autocmd!
augroup END

command! -nargs=* Autocmd autocmd AutoGroup <args>
command! -nargs=* AutocmdFT autocmd AutoGroup FileType <args>

" ----------------------------
" ---- File type settings ----
" ----------------------------
Autocmd BufNewFile,BufRead *.go,*go.mod set filetype=go
Autocmd BufNewFile,BufRead *.dart set filetype=dart
Autocmd BufNewFile,BufRead *.erls,*.erl set filetype=erlang
Autocmd BufNewFile,BufRead *.es6 set filetype=javascript
Autocmd BufNewFile,BufRead *.exs,*.ex set filetype=elixir
Autocmd BufNewFile,BufRead *.jsx set filetype=javascript.jsx
Autocmd BufNewFile,BufRead *.py set filetype=python
Autocmd BufNewFile,BufRead *.rb,*.rbw,*.gemspec setlocal filetype=ruby
Autocmd BufNewFile,BufRead *.rs set filetype=rust
Autocmd BufNewFile,BufRead *.tmpl set filetype=html
Autocmd BufNewFile,BufRead *.ts set filetype=typescript
Autocmd BufNewFile,BufRead *.{md,mdwn,mkd,mkdn,mark*} set filetype=markdown
Autocmd BufNewFile,BufRead *.{[Dd]ockerfile,[Dd]ock} set filetype=dockerfile
Autocmd BufNewFile,BufRead Dockerfile* set filetype=dockerfile
Autocmd BufNewFile,BufRead *.rasi set filetype=css

" ----------------------------
" ---- gitgutter settings ----
" ----------------------------
let g:gitgutter_max_signs = 10000
let g:gitgutter_git_executable = '/usr/bin/git'

" ---------------------
" ---- Caw Setting ----
" ---------------------
let g:caw_hatpos_skip_blank_line = 0
let g:caw_no_default_keymappings = 1
let g:caw_operator_keymappings = 0
nmap <C-C> <Plug>(caw:hatpos:toggle)
vmap <C-C> <Plug>(caw:hatpos:toggle)

" -------------------------
" ---- Default Setting ----
" -------------------------

set completeopt=menu,preview,noinsert

" ---- Enable Word Wrap
set wrap

" ---- Max Syntax Highlight Per Colmun
set synmaxcol=2000

" ---- highlight both bracket
set showmatch matchtime=2
set list listchars=tab:>\ ,trail:_,eol:↲,extends:»,precedes:«,nbsp:%

set display=lastline
" ---- 2spaces width for ambient
" set ambiwidth=double

" ---- incremental steps
set nrformats=""

" ---- Blockwise
set virtualedit=block

" ---- Filename Suggestion
set wildmenu
set wildmode=list:longest,full

" ---- auto reload when edited
set autoread
set autowrite

" ---- Disable Swap
set noswapfile

" ---- Disable Backup File
set nowritebackup

" ---- Disable Backup
set nobackup

" ---- link clipboard
set clipboard+=unnamedplus

" ---- Fix Current Window Position
set splitright
set splitbelow

" ---- Enable Incremental Search
set incsearch

" ---- Disable letter Distinction
set ignorecase
set wrapscan

" ---- Disable Search Result Distinction
set infercase

" ---- Disable Lower Upper
set smartcase

" ---- Always Shows Status line
set laststatus=2

" ---- Always Show cmd
set showcmd

" ---- Disable Beep Sound
set visualbell t_vb=
set novisualbell
set noerrorbells

" ---- convert to soft tab
set expandtab
set shiftwidth=4
set tabstop=4
set smarttab
set softtabstop=0
set autoindent
set smartindent

" ---- Indentation shiftwidth width
set shiftround

" ---- Visibility Tabs and EOL
set list

" ---- Free move cursor
set whichwrap=b,s,h,l,<,>,[,]

" ---- scrolls visibility
set scrolloff=5

" ---- Enhance Backspace
set backspace=indent,eol,start

" ---- Add <> pairs to bracket
set matchpairs+=<:>

" ---- open current buffer
set switchbuf=useopen

" ---- History Count
set history=100

" ---- Enable mouse Controll
set mouse=a
set guioptions+=a

" ---- Faster Scroll
set lazyredraw
set ttyfast

set viminfo='100,/50,%,<1000,f50,s100,:100,c,h,!
set shortmess+=I
set fileformat=unix
set fileformats=unix,dos,mac
set foldmethod=manual
if executable('zsh')
    set shell=zsh
endif

" --------------------------
" ----- Color Setting ------
" --------------------------
colorscheme monokai
highlight Normal ctermbg=none
let g:monokai_italic = 1
let g:monokai_thick_border = 1

" ----------------------
" ---- Key mappings ----
" ----------------------
cnoreabbrev W! w!
cnoreabbrev Q! q!
cnoreabbrev Qall! qall!
cnoreabbrev Wq wq
cnoreabbrev Wa wa
cnoreabbrev wQ wq
cnoreabbrev WQ wq
cnoreabbrev W w
cnoreabbrev Q q
cnoreabbrev Qall qall

" Returnキーは常に新しい行を追加するように
nnoremap <CR> o<Esc>

" シェルのカーソル移動コマンドを有効化
cnoremap <C-a> <Home>
inoremap <C-a> <Home>
cnoremap <C-e> <End>
inoremap <C-e> <End>
cnoremap <C-f> <Right>
inoremap <C-f> <Right>
cnoremap <C-b> <Left>
inoremap <C-b> <Left>

" 折り返した行を複数行として移動
nnoremap <silent> j gj
nnoremap <silent> k gk
nnoremap <silent> gj j
nnoremap <silent> gk k

" ウィンドウの移動をCtrlキーと方向指定でできるように
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Esc2回で検索のハイライトを消す
nnoremap <silent> <Esc><Esc> :<C-u>nohlsearch<CR>

" gをバインドキーとしたtmuxと同じキーバインドでタブを操作
nnoremap <silent> gc :<C-u>tabnew<CR>
nnoremap <silent> gx :<C-u>tabclose<CR>
nnoremap gn gt
nnoremap gp gT
" g+oで現在開いている以外のタブを全て閉じる
nnoremap <silent> go :<C-u>tabonly<CR>

noremap ; :
inoremap <C-j> <esc>
inoremap <C-s> <esc>:w<CR>
nnoremap <C-q> :qall<CR>

" ---- Enable Filetype
filetype plugin indent on
filetype on
