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
    let s:jetpackurl = "https://raw.githubusercontent.com/tani/vim-jetpack/main/plugin/jetpack.vim"
    if !filereadable(s:jetpackfile)
      call system(printf('curl -fsSLo %s --create-dirs %s', s:jetpackfile, s:jetpackurl))
    endif
endif

" -------------------------
" ---- Plugins Install ----
" -------------------------
packadd vim-jetpack
call jetpack#begin(expand('$NVIM_HOME'))
    Jetpack 'LumaKernel/ddc-file'
    Jetpack 'LumaKernel/ddc-tabnine'
    Jetpack 'Shougo/ddc-around' " sources
    Jetpack 'Shougo/ddc-converter_remove_overlap'
    Jetpack 'Shougo/ddc-matcher_head' " filters
    Jetpack 'Shougo/ddc-nvim-lsp'
    Jetpack 'Shougo/ddc-sorter_rank' " filters
    Jetpack 'Shougo/ddc.vim'
    Jetpack 'Shougo/deoppet.nvim', { 'do': ':UpdateRemotePlugins' }
    Jetpack 'Shougo/pum.vim'
    Jetpack 'airblade/vim-gitgutter'
    Jetpack 'editorconfig/editorconfig-vim'
    Jetpack 'mattn/vim-goimports', {'for': 'go'}
    Jetpack 'neovim/nvim-lspconfig'
    Jetpack 'sbdchd/neoformat'
    Jetpack 'tani/ddc-fuzzy'
    Jetpack 'tani/vim-jetpack', {'opt': 1}
    Jetpack 'tyru/caw.vim' " comment out
    Jetpack 'vim-denops/denops.vim', { 'branch': 'master' }
    Jetpack 'williamboman/mason-lspconfig.nvim'
    Jetpack 'williamboman/mason.nvim'
    Jetpack 'editorconfig/editorconfig-vim'
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
" ---- lspconfig settings ----
" ----------------------------
lua << EOF
local nvim_lsp = require('lspconfig')

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach = function(client, bufnr)
  local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

  --Enable completion triggered by <c-x><c-o>
  buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

  -- Mappings.
  local opts = { noremap=true, silent=true }

  -- See `:help vim.lsp.*` for documentation on any of the below functions
  buf_set_keymap('n', 'gD', '<Cmd>lua vim.lsp.buf.declaration()<CR>', opts)
  buf_set_keymap('n', 'gd', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
  buf_set_keymap('n', 'K', '<Cmd>lua vim.lsp.buf.hover()<CR>', opts)
  buf_set_keymap('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)
  buf_set_keymap('n', '<C-k>', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
  buf_set_keymap('n', '<space>wa', '<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
  buf_set_keymap('n', '<space>wr', '<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
  buf_set_keymap('n', '<space>wl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
  buf_set_keymap('n', '<space>D', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
  buf_set_keymap('n', '<space>rn', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
  buf_set_keymap('n', '<space>ca', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
  buf_set_keymap('n', 'gr', '<cmd>lua vim.lsp.buf.references()<CR>', opts)
  buf_set_keymap('n', '<space>e', '<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>', opts)
  buf_set_keymap('n', '[d', '<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>', opts)
  buf_set_keymap('n', ']d', '<cmd>lua vim.lsp.diagnostic.goto_next()<CR>', opts)
  buf_set_keymap('n', '<space>q', '<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>', opts)
  buf_set_keymap("n", "<space>f", "<cmd>lua vim.lsp.buf.formatting()<CR>", opts)
end

nvim_lsp.rust_analyzer.setup{
    on_attach = on_attach,
}

nvim_lsp.gopls.setup{
    on_attach = on_attach,
}

-- ----------------------
-- ---- ddc settings ----
-- ----------------------
 local mason = require('mason')
 mason.setup({
   ui = {
     icons = {
       package_installed = "✓",
       package_pending = "➜",
       package_uninstalled = "✗"
     }
   }
 })

 local mason_lspconfig = require('mason-lspconfig')
 mason_lspconfig.setup_handlers({ function(server_name)
   local opts = {}
   opts.on_attach = function(_, bufnr)
     local bufopts = { silent = true, buffer = bufnr }
     vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
     vim.keymap.set('n', 'gtD', vim.lsp.buf.type_definition, bufopts)
     vim.keymap.set('n', 'grf', vim.lsp.buf.references, bufopts)
     vim.keymap.set('n', '<space>p', vim.lsp.buf.format, bufopts)
  end
   nvim_lsp[server_name].setup(opts)
 end })
EOF

" --------------------------
" ---- ddc lsp settings ----
" --------------------------
call ddc#custom#patch_global('sources', ['nvim-lsp', 'tabnine', 'around', 'file'])
call ddc#custom#patch_global('sourceOptions', {
      \ '_': {
      \   'matchers': ['matcher_fuzzy', 'matcher_head'],
      \   'sorters': ['sorter_fuzzy', 'sorter_rank'],
      \   'converters': ['converter_fuzzy']
      \ },
      \ 'tabnine': {
      \   'mark': 'TN',
      \   'maxCandidates': 5,
      \   'isVolatile': v:true,
      \ },
      \ 'nvim-lsp': {
      \   'mark': 'lsp',
      \   'matchers': ['matcher_head'],
      \   'forceCompletionPattern': '\.\w*|:\w*|->\w*'
      \ },
      \ 'around': {'mark': 'A'},
      \ 'file': {
      \   'mark': 'file',
      \   'isVolatile': v:true,
      \   'forceCompletionPattern': '\S/\S*'
      \ }})

call ddc#custom#patch_global('sourceParams', {
      \ 'around': {'maxSize': 500},
      \ 'nvim-lsp': { 'kindLabels': { 'Class': 'c' } },
      \ })

inoremap <silent><expr> <TAB>
      \ ddc#map#pum_visible() ? '<C-n>' :
      \ (col('.') <= 1 <Bar><Bar> getline('.')[col('.') - 2] =~# '\s') ?
      \ '<TAB>' : ddc#map#manual_complete()
inoremap <expr><S-TAB>  ddc#map#pum_visible() ? '<C-p>' : '<C-h>'

" ----------------------------
" ---- ddc fuzzy settings ----
" ----------------------------
call ddc#custom#patch_global('completionMenu', 'pum.vim')
call ddc#custom#patch_global('filterParams', {
  \   'matcher_fuzzy': {
  \     'splitMode': 'word'
  \   },
  \   'converter_fuzzy': {
  \     'hlGroup': 'SpellBad'
  \   }
  \ })

" -----------------------------------------------------------------
" ---- ddc completion selector settings with ddc-fuzzy and pum ----
" -----------------------------------------------------------------
inoremap <C-e>   <Cmd>call pum#map#cancel()<CR>
inoremap <C-n>   <Cmd>call pum#map#insert_relative(+1)<CR>
inoremap <C-p>   <Cmd>call pum#map#select_relative(-1)<CR>
inoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
inoremap <PageDown> <Cmd>call pum#map#insert_relative_page(+1)<CR>
inoremap <PageUp>   <Cmd>call pum#map#insert_relative_page(-1)<CR>
inoremap <S-Tab> <Cmd>call pum#map#insert_relative(-1)<CR>

inoremap <silent><expr> <TAB>
      \ pum#visible() ? '<Cmd>call pum#map#insert_relative(+1)<CR>' :
      \ (col('.') <= 1 <Bar><Bar> getline('.')[col('.') - 2] =~# '\s') ?
      \ '<TAB>' : ddc#manual_complete()

inoremap <silent><expr> <Down>
      \ pum#visible() ? '<Cmd>call pum#map#select_relative(+1)<CR>' :
      \ '<Down>'
inoremap <silent><expr> <Up>
      \ pum#visible() ? '<Cmd>call pum#map#select_relative(-1)<CR>' :
      \ '<Up>'
inoremap <silent><expr> <CR>
      \ pum#visible() ? '<Cmd>call pum#map#confirm()<CR>' :
      \ '<CR>'

call ddc#custom#patch_global('autoCompleteEvents', [
    \ 'InsertEnter', 'TextChangedI', 'TextChangedP',
    \ 'CmdlineEnter', 'CmdlineChanged',
    \ ])

" nnoremap :       <Cmd>call CommandlinePre()<CR>:
"
" function! CommandlinePre() abort
"   " Note: It disables default command line completion!
"   cnoremap <expr> <Tab>
"  \ pum#visible() ? '<Cmd>call pum#map#insert_relative(+1)<CR>' :
"  \ ddc#manual_complete()
"   cnoremap <S-Tab> <Cmd>call pum#map#insert_relative(-1)<CR>
"   cnoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
"   cnoremap <C-e>   <Cmd>call pum#map#cancel()<CR>
"
"   " Overwrite sources
"   if !exists('b:prev_buffer_config')
"     let b:prev_buffer_config = ddc#custom#get_buffer()
"   endif
"   call ddc#custom#patch_buffer('sources',
"          \ ['cmdline', 'cmdline-history', 'around'])
"
"   autocmd User DDCCmdlineLeave ++once call CommandlinePost()
"   autocmd InsertEnter <buffer> ++once call CommandlinePost()
"
"   " Enable command line completion
"   call ddc#enable_cmdline_completion()
" endfunction
"
" function! CommandlinePost() abort
"   cunmap <Tab>
"   cunmap <S-Tab>
"   cunmap <C-y>
"   cunmap <C-e>
"
"   " Restore sources
"   if exists('b:prev_buffer_config')
"     call ddc#custom#set_buffer(b:prev_buffer_config)
"     unlet b:prev_buffer_config
"   else
"     call ddc#custom#set_buffer({})
"   endif
" endfunction

" --------------------
" ---- enable ddc ----
" --------------------
call ddc#enable()

" --------------------------
" ---- deoppet settings ----
" --------------------------
call deoppet#initialize()
call deoppet#custom#option('snippets',
\ map(globpath(&runtimepath, 'neosnippets', 1, 1),
\     { _, val -> { 'path': val } }))

imap <C-k>  <Plug>(deoppet_expand)
imap <C-f>  <Plug>(deoppet_jump_forward)
imap <C-b>  <Plug>(deoppet_jump_backward)
smap <C-f>  <Plug>(deoppet_jump_forward)
smap <C-b>  <Plug>(deoppet_jump_backward)

" Use deoppet source.
call ddc#custom#patch_global('sources', ['deoppet'])

" Change source options
call ddc#custom#patch_global('sourceOptions', {
      \ 'deoppet': {'dup': v:true, 'mark': 'dp'},
      \ })

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

" set helplang=ja

" ---- Enable Word Wrap
set wrap

" ---- Max Syntax Highlight Per Colmun
set synmaxcol=2000

" ---- highlight both bracket
set showmatch matchtime=2
set listchars=tab:>\ ,trail:_,eol:↲,extends:»,precedes:«,nbsp:%

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
set showbreak=↪

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
inoremap <silent> jj <Esc>
inoremap <silent> っj <ESC>

" ウィンドウの移動をCtrlキーと方向指定でできるように
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

inoremap <C-j> <Down>
inoremap <C-k> <Up>
inoremap <C-h> <Left>
inoremap <C-l> <Right>

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

inoremap { {}<LEFT>
inoremap [ []<LEFT>
inoremap ( ()<LEFT>
inoremap " ""<LEFT>
inoremap ' ''<LEFT>
let &t_SI = "\<Esc>]50;CursorShape=1\x7"
let &t_EI = "\<Esc>]50;CursorShape=0\x7"
inoremap <Esc> <Esc>lh

" ---- Enable Filetype
filetype plugin indent on
filetype on
