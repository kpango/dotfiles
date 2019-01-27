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
" ---- Install vim-plug ----
" --------------------------
if has('vim_starting')
    set runtimepath+=~/.config/nvim/plugged/vim-plug
    if !isdirectory(expand('$NVIM_HOME') . '/plugged/vim-plug')
        call system('mkdir -p ~/.config/nvim/plugged/vim-plug')
        call system('git clone https://github.com/junegunn/vim-plug.git ~/.config/nvim/plugged/vim-plug/autoload')
    end
endif

" let g:ale_completion_enabled = 1

" -------------------------
" ---- Plugins Install ----
" -------------------------
call plug#begin(expand('$NVIM_HOME') . '/plugged')
" ----- update self
    Plug 'junegunn/vim-plug', {'dir': expand('$NVIM_HOME') . '/plugged/vim-plug/autoload'}
" ---- common plugins
    Plug 'Shougo/context_filetype.vim' " auto detect filetype
    Plug 'Shougo/denite.nvim', {'do': ':UpdateRemotePlugins' }
    " Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
    " Plug 'Shougo/neoinclude.vim'
    " TODO if deoppet is fully worked replace neosnippet
    " Plug 'Shougo/deoppet.nvim', { 'do': ':UpdateRemotePlugins' }
    " Plug 'Shougo/neosnippet'
    " Plug 'Shougo/neosnippet-snippets'
    Plug 'Shougo/neoyank.vim'
    Plug 'Shougo/vimproc.vim', {'dir': expand('$NVIM_HOME') . '/plugged/vimproc.vim', 'do': 'make' }
    Plug 'Shougo/neomru.vim'
    Plug 'cohama/lexima.vim' " auto close bracket
    Plug 'airblade/vim-gitgutter'
    Plug 'itchyny/lightline.vim'
    Plug 'janko-m/vim-test', {'for': ['go','rust','elixir','python','ruby','javascript','sh','lua','php','perl','java']}
    Plug 'sbdchd/neoformat' ", {'for', '!go'}
    " Plug 'junegunn/fzf', { 'dir': expand('$NVIM_HOME') . '/plugged/fzf', 'do': expand('$NVIM_HOME') . '/plugged/fzf/install --all' }
    " Plug 'junegunn/vim-easy-align', {'on': 'EasyAlign'}
    Plug 'lilydjwg/colorizer', {'do': 'make'} " colorize rgb rgba texts
    Plug 'majutsushi/tagbar' " tag bar toggle
    Plug 'nathanaelkane/vim-indent-guides' " show indent guide
    Plug 'w0rp/ale' " lint plugin
    Plug 'tyru/caw.vim' " comment out
    Plug 'rizzatti/dash.vim', {'on': 'Dash'}
    Plug 'sjl/gundo.vim', {'on': 'GundoToggle'}
    Plug 'terryma/vim-multiple-cursors' " multiple cursors
    Plug 'thinca/vim-quickrun'
    Plug 'tpope/vim-surround'
    Plug 'vim-scripts/sudo.vim'
    " Plug 'ozelentok/denite-gtags'
    " Plug 'jsfaint/gen_tags.vim'
    " Plug 'vim-scripts/gtags.vim'
    " Plug 'autozimu/LanguageClient-neovim', {
        "\ 'branch': 'next',
        "\ 'do': 'zsh install.sh',
        "\ }
    Plug 'prabirshrestha/async.vim'
    Plug 'prabirshrestha/vim-lsp'
    Plug 'prabirshrestha/asyncomplete.vim'
    Plug 'prabirshrestha/asyncomplete-lsp.vim'
    " Plug 'natebosch/vim-lsc'
" ---- Vim Setting
    Plug 'Shougo/neco-vim', {'for': 'vim'}
    Plug 'Shougo/neco-syntax', {'for': 'vim'}
" ---- Yaml Setting
    Plug 'stephpy/vim-yaml', {'for': ['yaml','yml']}
" ---- Clang Setting
    " Plug 'zchee/deoplete-clang', {'for': ['c', 'cpp', 'cxx', 'cmake', 'clang']}
" ---- Golang Setting
    Plug 'fatih/vim-go', {'for': 'go', 'do': 'GoInstallBinaries'} " go defact standard vim plugin
    Plug 'jodosha/vim-godebug', {'for': 'go'} " delve Debuger
    " Plug 'zchee/deoplete-go', {'for': 'go', 'do': 'make'} " for completion
    Plug 'buoto/gotests-vim', {'for': 'go', 'on': 'GoTests'} " generates test code
    Plug 'tweekmonster/hl-goimport.vim', {'for': 'go'} " highlight package name
" ---- HTML
    Plug 'digitaltoad/vim-jade', { 'for': ['jade', 'pug'] }
    Plug 'gregsexton/MatchTag', { 'for': ['html','php'] }
    Plug 'hokaccha/vim-html5validator', {'for': ['html', 'php']}
    Plug 'mattn/emmet-vim', {'for': ['html', 'php']}
    Plug 'mustache/vim-mustache-handlebars', { 'for': ['html','php','haml'] }
    Plug 'othree/html5.vim', {'for': ['html', 'php']}
    Plug 'tpope/vim-haml', {'for': 'haml'}
" ---- LESS SASS CSS
    Plug 'ap/vim-css-color', {'for': ['css','less','sass','scss','stylus'] }
    Plug 'cakebaker/scss-syntax.vim', { 'for': ['sass','scss'] }
    Plug 'groenewege/vim-less', {'for': 'less'}
    Plug 'hail2u/vim-css3-syntax', {'for': ['css','less','sass','scss','stylus'] }
    Plug 'wavded/vim-stylus', {'for': ['stylus']}
" ---- JavaScript
    Plug 'ryanolsonx/vim-lsp-javascript', { 'for': ['js', 'javascript', 'javascript.jsx', 'json', 'vue'] }
    Plug 'ryanolsonx/vim-lsp-typescript', { 'for': 'typescript' }
    " Plug 'ternjs/tern_for_vim', { 'for': ['javascript', 'javascript.jsx'] }
    " Plug 'carlitux/deoplete-ternjs', { 'for': ['js', 'javascript', 'javascript.jsx', 'json', 'vue'], 'do': 'npm install -g tern' }
    " Plug 'itspriddle/vim-jquery', {'for': ['javascript', 'javascript.jsx', 'html']}
    " Plug 'jason0x43/vim-js-indent', { 'for': ['javascript', 'javascript.jsx', 'typescript', 'html'] }
    " Plug 'kchmck/vim-coffee-script', {'for': 'coffee'}
    " Plug 'leafgarland/typescript-vim', { 'for': 'typescript' }
    " Plug 'mhartington/deoplete-typescript', { 'for': 'typescript' }
    " Plug 'mxw/vim-jsx', { 'for': ['javascript.jsx'] }
    " Plug 'posva/vim-vue', { 'for': ['vue'] }
    " Plug 'othree/jspc.vim', { 'for': ['js', 'javascript', 'javascript.jsx', 'json', 'vue'] }
    " Plug 'othree/yajs.vim', { 'for': ['js', 'javascript', 'javascript.jsx', 'json', 'vue'] }
    " Plug 'pangloss/vim-javascript', { 'for': ['javascript', 'javascript.jsx'] }
    " Plug 'ramitos/jsctags', {'for': ['javascript', 'javascript.jsx', 'json']}
" ---- Dart
    Plug 'dart-lang/dart-vim-plugin', {'for': 'dart'}
    Plug 'miyakogi/vim-dartanalyzer', {'for': 'dart'}
" ---- Crystal
    Plug 'rhysd/vim-crystal', {'for': ['crystal'] }
" ---- Nim
    Plug 'zah/nim.vim', {'for': 'nim'}
" ---- Rust
    Plug 'rust-lang/rust.vim', {'for': 'rust'}
    " Plug 'sebastianmarkow/deoplete-rust', {'for': 'rust'}
    Plug 'rhysd/rust-doc.vim', {'for': 'rust', 'on': ['RustDoc', 'Denite']}
" ---- Python
    " Plug 'zchee/deoplete-jedi', {'for': ['python', 'python3','djangohtml'], 'do': 'pip install jedi;pip3 install jedi'}
    Plug 'ryanolsonx/vim-lsp-python', {'for': ['python', 'python3','djangohtml'] }
" ---- Lisp
    Plug 'vim-scripts/slimv.vim', {'for': 'lisp'}
" ---- Lua
    Plug 'xolox/vim-misc', {'for': 'lua'}
    Plug 'xolox/vim-lua-ftplugin', {'for': 'lua'}
    Plug 'xolox/vim-lua-inspect', {'for': 'lua'}
" ---- Swift
    Plug 'keith/swift.vim', {'for': 'swift'}
    Plug 'kballard/vim-swift', {'for': 'swift'}
"     Plug 'landaire/deoplete-swift', {'for': 'swift'}
    Plug 'mitsuse/autocomplete-swift', {'for': 'swift'}
" ---- Markdown
    Plug 'kannokanno/previm', {'for': 'markdown'}
    Plug 'plasticboy/vim-markdown', {'for': 'markdown'}
    Plug 'shinespark/vim-list2tree', {'for': 'markdown', 'on': 'List2Tree'}
    Plug 'sotte/presenting.vim', {'for': 'markdown'}
    Plug 'tyru/open-browser.vim', {'for': 'markdown'}
" ---- SQL
    Plug 'JarrodCTaylor/vim-sql-suggest', { 'for': 'sql' }
" ---- TOML
    Plug 'cespare/vim-toml', {'for': 'toml'}
" ---- LLVM
    Plug 'qnighy/llvm.vim', {'for': 'llvm'}
" ---- ZSH
    " Plug 'zchee/deoplete-zsh', {'for': 'zsh'}
call plug#end()

" --------------------------------------
" ---- Plugin Dependencies Settings ----
" --------------------------------------
if !has('python') && !has('pip')
    call system('pip install --upgrade pip')
    call system('pip install neovim --upgrade')
endif

if !has('python3') && !has('pip3')
    call system('pip3 install --upgrade pip')
    call system('pip3 install neovim --upgrade')
endif

if !has('gb') && has('go')
    call system('go get -u -v github.com/constabulary/gb/...')
endif

let g:python_host_skip_check = 1
let g:python2_host_skip_check = 1
let g:python3_host_skip_check = 1

if executable('python2')
    let g:python_host_prog=system('which python2')
endif

if executable('python3')
    let g:python3_host_prog=system('which python3')
endif

" ----------------------------
" ---- AutoGroup Settings ----
" ----------------------------
augroup AutoGroup
    autocmd!
augroup END

command! -nargs=* Autocmd autocmd AutoGroup <args>
command! -nargs=* AutocmdFT autocmd AutoGroup FileType <args>

" ---------------------------
" ---- Deoplete Settings ----
" ---------------------------
" set runtimepath+=globpath($NVIM_HOME,"/plugged/deoplete.nvim")
" let g:deoplete#enable_at_startup = 1
" let g:deoplete#auto_complete_delay = 0
" let g:deoplete#auto_complete_start_length = 1
" let g:deoplete#auto_completion_start_length = 1
" let g:deoplete#enable_camel_case = 1
" let g:deoplete#enable_ignore_case = 1
" let g:deoplete#enable_refresh_always = 1
" let g:deoplete#enable_smart_case = 1
" let g:deoplete#file#enable_buffer_path = 1
" let g:deoplete#max_list = 10000

" TODO remove it
" let g:neosnippet#snippets_directory=expand('$NVIM_HOME') . '/plugged/neosnippet-snippets/neosnippets/'
" TODO if deoppet is fully worked replace neosnippet
" let g:deoppet#snippets_directory=expand('$NVIM_HOME') . '/plugged/neosnippet-snippets/neosnippets/'

" Deoplete-Golang
" AutocmdFT go call deoplete#custom#source('go', 'matchers', ['matcher_full_fuzzy'])
" AutocmdFT go call deoplete#custom#source('go', 'sorters', [])
" AutocmdFT go let g:deoplete#sources#go#align_class = 1
" " AutocmdFT go let g:deoplete#sources#go#cgo = 1
" " AutocmdFT go let g:deoplete#sources#go#cgo#libclang_path= expand("/Library/Developer/CommandLineTools/usr/lib/libclang.dylib")
" " AutocmdFT go let g:deoplete#sources#go#cgo#sort_algo = 'alphabetical'
" AutocmdFT go let g:deoplete#sources#go#gocode_binary = globpath($GOPATH,"/bin/gocode")
" AutocmdFT go let g:deoplete#sources#go#json_directory = globpath($NVIM_HOME,"/plugged/deoplete-go/data/json/*/").expand("$GOOS")."_".expand("$GOARCH")
" AutocmdFT go let g:deoplete#sources#go#package_dot = 1
" AutocmdFT go let g:deoplete#sources#go#on_event = 1
" AutocmdFT go let g:deoplete#sources#go#pointer = 1
" AutocmdFT go let g:deoplete#sources#go#sort_class = ['package', 'func', 'type', 'var', 'const']
" AutocmdFT go let g:deoplete#sources#go#use_cache = 1
"
" " Deoplete-Clang
" AutocmdFT c,cpp,clang,hpp,cxx let g:deoplete#sources#clang#libclang_path= expand("/Library/Developer/CommandLineTools/usr/lib/libclang.dylib")
" AutocmdFT c,cpp,clang,hpp,cxx let g:deoplete#sources#clang#clang_header = expand("/Library/Developer/CommandLineTools/usr/lib/clang")
"
" " Deoplete Python
" AutocmdFT python let g:deoplete#sources#jedi#enable_cache = 1
" AutocmdFT python let g:deoplete#sources#jedi#statement_length = 0
" AutocmdFT python let g:deoplete#sources#jedi#short_types = 0
" AutocmdFT python let g:deoplete#sources#jedi#show_docstring = 1
" AutocmdFT python let g:deoplete#sources#jedi#worker_threads = 4
" AutocmdFT python call deoplete#custom#source('jedi', 'disabled_syntaxes', ['Comment'])
" AutocmdFT python call deoplete#custom#source('jedi', 'matchers', ['matcher_fuzzy'])
"
" " Deoplete Rust
" AutocmdFT rust let g:deoplete#sources#rust#racer_binary = globpath("$HOME",".cargo/bin/racer")
" AutocmdFT rust let g:deoplete#sources#rust#rust_source_path = expand("$RUST_SRC_PATH")
" AutocmdFT rust let g:deoplete#sources#rust#documentation_max_height=20
"
" " Deoplete Swift
" AutocmdFT swift let g:deoplete#sources#swift#source_kitten_binary = system("which sourcekitten")

" ----------------------
" ---- Ale settings ----
" ----------------------
let g:ale_enabled = 1
let g:ale_keep_list_window_open = 0
let g:ale_list_window_size = 5
let g:ale_open_list = 1
let g:ale_set_highlights = 1
" let g:ale_set_loclist = 0
" let g:ale_set_quickfix = 1
let g:ale_warn_about_trailing_whitespace = 0
let g:ale_linters = {
        \   'javascript': ['eslint_d'],
        \   'php': ['php', 'phpcs', 'phpmd'],
        \   'go': ['go build', 'gometalinter'],
        \   'rust': ['rustc'],
        \   'html': ['tidy', 'htmlhint'],
        \   'c': ['clang'],
        \   'cpp': ['clang++'],
        \   'css': ['csslint', 'stylelint'],
        \   'nim': ['nim', 'nimsuggest'],
        \   'vim': ['vint'],
        \   'python': ['python', 'pyflakes', 'flake8'],
        \   'shell': ['sh', 'shellcheck'],
        \   'zsh': ['zsh'],
        \   'swift': ['swiftc'],
        \   'sql': ['sqlint'],
        \}
let g:ale_lint_on_text_changed = 'never'
let g:ale_lint_on_save = 1
let g:ale_lint_on_enter = 1
let g:ale_sign_column_always = 1
let g:ale_sign_error = '⨉'
let g:ale_sign_warning = '⚠'
let g:ale_sign_info = 'i'
let g:ale_statusline_format = ['%d error(s)', '%d warning(s)', 'OK']
let g:ale_echo_cursor = 1
let g:ale_echo_msg_error_str = 'ERROR'
let g:ale_echo_msg_warning_str = 'WARNING'
let g:ale_echo_msg_format = '[%linter%] %s [%severity%]'
" let g:ale_go_langserver_executable = "bingo"
" let g:ale_go_langserver_options = "-mode stdio"
nnoremap <silent> <C-k> <Plug>(ale_previous_wrap)
nnoremap <silent> <C-j> <Plug>(ale_next_wrap)
" Close Quickfix list when file leave
Autocmd WinEnter * if (winnr('$') == 1) && (getbufvar(winbufnr(0), '&buftype')) == 'quickfix' | quit | endif

AutocmdFT go let g:ale_go_gometalinter_options = '--tests --disable-all --aggregate --fast --sort=line --vendor --concurrency=16  --enable=gocyclo --enable=govet --enable=golint --enable=gotype'


" --------------------------------------------------
" ---- Language Server Protocol Client settings ----
" --------------------------------------------------
imap <c-space> <Plug>(asyncomplete_force_refresh)
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <cr> pumvisible() ? "\<C-y>\<cr>" : "\<cr>"
autocmd! CompleteDone * if pumvisible() == 0 | pclose | endif
" let g:LanguageClient_serverCommands = {
"    \ 'rust': ['rustup', 'run', 'nightly', 'rls'],
"    \ 'javascript': ['javascript-typescript-stdio'],
"    \ 'vue': ['vls'],
"    \ }
let g:lsp_async_completion = 1
let g:lsp_diagnostics_enabled = 0
let g:asyncomplete_remove_duplicates = 1
let g:asyncomplete_smart_completion = 1
let g:asyncomplete_auto_popup = 1

if executable('bingo')
    AutocmdFT go call lsp#register_server({
       \ 'name': 'go-lang',
       \ 'cmd': {server_info->['bingo', '--golist-duration', '0', '-mode', 'stdio']},
       \ 'whitelist': ['go'],
       \ })
endif

if executable('rls')
    AutocmdFT rust call lsp#register_server({
       \ 'name': 'rls',
       \ 'cmd': {server_info->['rustup', 'run', 'nightly', 'rls']},
       \ 'root_uri':{server_info->lsp#utils#path_to_uri(lsp#utils#find_nearest_parent_file_directory(lsp#utils#get_buffer_path(), 'Cargo.toml'))},
       \ 'whitelist': ['rust'],
       \ })
endif

if executable('docker-langserver')
    AutocmdFT dockerfile call lsp#register_server({
       \ 'name': 'docker-langserver',
       \ 'cmd': {server_info->[&shell, &shellcmdflag, 'docker-langserver --stdio']},
       \ 'whitelist': ['dockerfile'],
       \ })
endif

if executable('typescript-language-server')
    AutocmdFT javascript call lsp#register_server({
     \ 'name': 'javascript support using typescript-language-server',
     \ 'cmd': {server_info->[&shell, &shellcmdflag, 'typescript-language-server --stdio']},
     \ 'root_uri':{server_info->lsp#utils#path_to_uri(lsp#utils#find_nearest_parent_file_directory(lsp#utils#get_buffer_path(), 'package.json'))},
     \ 'whitelist': ['javascript', 'javascript.jsx', 'json', 'jsx', 'vue']
     \ })

    AutocmdFT typescript call lsp#register_server({
       \ 'name': 'typescript-language-server',
       \ 'cmd': {server_info->[&shell, &shellcmdflag, 'typescript-language-server --stdio']},
       \ 'root_uri':{server_info->lsp#utils#path_to_uri(lsp#utils#find_nearest_parent_file_directory(lsp#utils#get_buffer_path(), 'tsconfig.json'))},
       \ 'whitelist': ['typescript', 'typescript.tsx'],
       \ })
endif

if executable('pyls')
    AutocmdFT python call lsp#register_server({
       \ 'name': 'pyls',
       \ 'cmd': {server_info->['pyls']},
       \ 'whitelist': ['python'],
       \ 'workspace_config': {'pyls': {'plugins': {'pydocstyle': {'enabled': v:true}}}}
       \ })
endif
"
" -------------------------
" ---- Denite settings ----
" -------------------------
nnoremap <silent> <C-k><C-f> :<C-u>Denite file_rec<CR>
nnoremap <silent> <C-k><C-g> :<C-u>Denite grep -mode=normal -buffer-name=search-buffer-denite<CR>
nnoremap <silent> <C-k><C-r> :<C-u>Denite -resume -buffer-name=search-buffer-denite<CR>
nnoremap <silent> <C-k><C-n> :<C-u>Denite -resume -buffer-name=search-buffer-denite -select=+1 -immediately<CR>
nnoremap <silent> <C-k><C-p> :<C-u>Denite -resume -buffer-name=search-buffer-denite -select=-1 -immediately<CR>
nnoremap <silent> <C-k><C-l> :<C-u>Denite line<CR>
nnoremap <silent> <C-k><C-u> :<C-u>Denite file_mru -mode=normal buffer<CR>
nnoremap <silent> <C-k><C-y> :<C-u>Denite neoyank<CR>
nnoremap <silent> <C-k><C-b> :<C-u>Denite buffer<CR>

" 選択しているファイルをsplitで開く
call denite#custom#map('_', '<C-h>','<denite:do_action:split>')
call denite#custom#map('insert', '<C-h>','<denite:do_action:split>')
" 選択しているファイルをvsplitで開く
call denite#custom#map('_', '<C-v>','<denite:do_action:vsplit>')
call denite#custom#map('insert','<C-v>', '<denite:do_action:vsplit>')
" jjコマンドで標準モードに戻る
call denite#custom#map('insert', 'jj', '<denite:enter_mode:normal>')
" ESCキーでdeniteを終了
call denite#custom#map('insert', '<esc>', '<denite:enter_mode:normal>', 'noremap')
call denite#custom#map('normal', '<esc>', '<denite:quit>', 'noremap')

if executable('rg')
    call denite#custom#var('file_rec', 'command', ['rg', '--files', '--glob', '!.git'])
    call denite#custom#var('grep', 'command', ['rg'])
    call denite#custom#var('grep', 'recursive_opts', [])
    call denite#custom#var('grep', 'final_opts', [])
    call denite#custom#var('grep', 'separator', ['--'])
    call denite#custom#var('grep', 'default_opts', ['--vimgrep', '--no-heading'])
else
    call denite#custom#var('file_rec', 'command', ['ag', '--follow', '--nocolor', '--nogroup', '-g', ''])
endif
"
" " プロンプトの左端に表示される文字を指定
" call denite#custom#option('default', 'prompt', '>')
" " deniteの起動位置をtopに変更
" "call denite#custom#option('default', 'direction', 'top')

" ------------------------------
" ---- Status line settings ----
" ------------------------------
set statusline+=%#warningmsg#
set statusline+=%{ALEGetStatusLine()}
set statusline+=%*

" ----------------------------
" ---- File type settings ----
" ----------------------------
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
Autocmd BufRead,BufNewFile *.{[Dd]ockerfile,[Dd]ock} set filetype=dockerfile
Autocmd BufRead,BufNewFile Dockerfile* set filetype=dockerfile

" ------------------------------
" ---- Indentation settings ----
" ------------------------------
let g:indent_guides_enable_on_vim_startup=1
let g:indent_guides_start_level=2
let g:indent_guides_auto_colors=0
let g:indent_guides_color_change_percent = 30
let g:indent_guides_guide_size = 1

AutocmdFT coffee,javascript,javascript.jsx,jsx,json setlocal sw=2 sts=2 ts=2 expandtab completeopt=menu,preview omnifunc=nodejscomplete#CompleteJS omnifunc=lsp#complete
AutocmdFT go setlocal noexpandtab sw=4 ts=4 completeopt=menu,preview omnifunc=lsp#complete
" AutocmdFT go setlocal noexpandtab sw=4 ts=4 completeopt=menu,menuone,preview,noselect,noinsert
AutocmdFT html,xhtml setlocal smartindent expandtab ts=2 sw=2 sts=2 completeopt=menu,preview
AutocmdFT nim setlocal noexpandtab sw=4 ts=4 completeopt=menu,preview
AutocmdFT python setlocal smartindent expandtab sw=4 ts=8 sts=4 colorcolumn=79 completeopt=menu,preview formatoptions+=croq cinwords=if,elif,else,for,while,try,except,finally,def,class,with omnifunc=lsp#complete
AutocmdFT rust setlocal smartindent expandtab ts=4 sw=4 sts=4 completeopt=menu,preview omnifunc=lsp#complete
AutocmdFT sh,zsh,markdown setlocal expandtab ts=4 sts=4 sw=4 completeopt=menu,preview
AutocmdFT xml setlocal smartindent expandtab ts=2 sw=2 sts=2 completeopt=menu,preview

" --------------------------
" ---- Tag bar settings ----
" --------------------------
nmap <F8> :TagbarToggle<CR>
set updatetime=300

let g:tagbar_left = 0
let g:tagbar_autofocus = 1
AutocmdFT go let g:tagbar_type_go = {
                \ 'ctagstype' : 'go',
                \ 'kinds'     : [
                    \ 'p:package',
                    \ 'i:imports',
                    \ 'c:constants',
                    \ 'v:variables',
                    \ 't:types',
                    \ 'n:interfaces',
                    \ 'w:fields',
                    \ 'e:embedded',
                    \ 'm:methods',
                    \ 'r:constructor',
                    \ 'f:functions'
                \ ],
                \ 'sro' : '.',
                \ 'kind2scope' : {
                    \ 't' : 'ctype',
                    \ 'n' : 'ntype'
                \ },
                \ 'scope2kind' : {
                    \ 'ctype' : 't',
                    \ 'ntype' : 'n'
                \ },
                \ 'ctagsbin'  : 'gotags',
                \ 'ctagsargs' : '-sort -silent'
            \ }
AutocmdFT nim let g:tagbar_type_nim = {
            \ 'ctagstype' : 'nim',
            \ 'kinds' : [
            \   'h:Headline',
            \   't:class',
            \   't:enum',
            \   't:tuple',
            \   't:subrange',
            \   't:proctype',
            \   'f:procedure',
            \   'f:method',
            \   'o:operator',
            \   't:template',
            \   'm:macro',
            \ ],
            \ }
AutocmdFT ruby let g:tagbar_type_ruby = {
            \ 'ctagstype' : 'ruby',
            \ 'kinds' : [
            \   'm:modules',
            \   'c:classes',
            \   'd:describes',
            \   'C:contexts',
            \   'f:methods',
            \   'F:singleton methods'
            \ ]
            \}

" -------------------------
" ---- Format settings ----
" -------------------------
"  JSON Formatter
if executable('jq')
    function! s:jq(has_bang, ...) abort range
        execute 'silent' a:firstline ',' a:lastline '!jq' string(a:0 == 0 ? '.' : a:1)
        if !v:shell_error || a:has_bang
            return
        endif
        let l:error_lines = filter(getline('1', '$'), 'v:val =~# "^parse error: "')
        " 範囲指定している場合のために，行番号を置き換える
        let l:error_lines = map(l:error_lines, 'substitute(v:val, "line \\zs\\(\\d\\+\\)\\ze,", "\\=(submatch(1) + a:firstline - 1)", "")')
        let l:winheight = len(l:error_lines) > 10 ? 10 : len(l:error_lines)
        " カレントバッファがエラーメッセージになっているので，元に戻す
        undo
        " カレントバッファの下に新たにウィンドウを作り，エラーメッセージを表示するバッファを作成する
        execute 'botright' l:winheight 'new'
        setlocal nobuflisted bufhidden=unload buftype=nofile
        call setline(1, l:error_lines)
        " エラーメッセージ用バッファのundo履歴を削除(エラーメッセージをundoで消去しないため)
        let l:save_undolevels = &l:undolevels
        setlocal undolevels=-1
        execute "normal! a \<BS>\<Esc>"
        setlocal nomodified
        let &l:undolevels = l:save_undolevels
        " エラーメッセージ用バッファは読み取り専用にしておく
        setlocal readonly
    endfunction
    command! -bar -bang -range=% -nargs=? Jq <line1>,<line2>call s:jq(<bang>0, <f-args>)
endif

" -------------------------
" ---- Lexima settings ----
" -------------------------
call lexima#add_rule({'char': '$', 'input_after': '$', 'filetype': 'latex'})
call lexima#add_rule({'char': '$', 'at': '\%#\$', 'leave': 1, 'filetype': 'latex'})
call lexima#add_rule({'char': '<BS>', 'at': '\$\%#\$', 'delete': 1, 'filetype': 'latex'})
call lexima#add_rule({'at': '\%#.*[-0-9a-zA-Z_,:]', 'char': '{', 'input': '{'})
call lexima#add_rule({'at': '\%#\n\s*}', 'char': '}', 'input': '}', 'delete': '}'})

" ----------------------------
" ---- gitgutter settings ----
" ----------------------------
let g:gitgutter_max_signs = 10000
let g:gitgutter_git_executable="/usr/bin/git"

" ---------------------
" ---- Caw Setting ----
" ---------------------
let g:caw_hatpos_skip_blank_line = 0
let g:caw_no_default_keymappings = 1
let g:caw_operator_keymappings = 0
nmap <C-C> <Plug>(caw:hatpos:toggle)
vmap <C-C> <Plug>(caw:hatpos:toggle)

" -------------------------
" ---- Golang settings ----
" -------------------------
Autocmd BufWinEnter *.go GoFmt
Autocmd BufWritePre *.go GoFmt
AutocmdFT go compiler go
AutocmdFT go :highlight goExtraVars cterm=bold ctermfg=214
AutocmdFT go :match goExtraVars /\<ok\>\|\<err\>/
AutocmdFT go let g:go_fmt_command = "goimports"
" TODO if deoppet is fully worked replace neosnippet
" AutocmdFT go let g:go_snippet_engine = "deoppet"
" TODO remove this
" AutocmdFT go let g:go_snippet_engine = "neosnippet"
AutocmdFT go let g:go_def_mapping_enabled = 0
AutocmdFT go let g:go_doc_keywordprg_enabled = 0
AutocmdFT go let g:go_highlight_types = 1
AutocmdFT go let g:go_highlight_fields = 1
AutocmdFT go let g:go_highlight_functions = 1
AutocmdFT go let g:go_highlight_methods = 1
AutocmdFT go let g:go_highlight_structs = 1
AutocmdFT go let g:go_highlight_operators = 1
AutocmdFT go let g:go_highlight_build_constraints = 1
AutocmdFT go let g:go_highlight_extra_types = 1
AutocmdFT go let g:go_auto_type_info = 1
AutocmdFT go let g:go_auto_sameids = 1
AutocmdFT go let g:go_list_type = "quickfix"
AutocmdFT go let g:go_addtags_transform = "snakecase"
AutocmdFT go let g:go_alternate_mode = "edit"
AutocmdFT go set runtimepath+=globpath($GOROOT, "/misc/vim")
" AutocmdFT go set runtimepath+=globpath($GOPATH, "src/github.com/nsf/gocode/vim")
AutocmdFT go nnoremap <F5> :Gorun<CR>
AutocmdFT go nnoremap gd <Plug>(go-def-split)

" ------------------------
" ---- Clang settings ----
" ------------------------
Autocmd BufWritePre *.cpp,*.c,*.cc,*.hpp call vimproc#system_bg("clang-format -style='Google' -i " . expand("%"))

" ---------------------------
" ---- protobuf settings ----
" ---------------------------
Autocmd BufWritePre *.proto,*.pb,*.protobuf Neoformat

" ----------------------
" ---- Nim settings ----
" ----------------------
AutocmdFT nim let g:nvim_nim_enable_async = 0

" -----------------------
" ---- Rust settings ----
" -----------------------
Autocmd BufWritePre *.rust RustFmt
AutocmdFT BufWritePost *.rs QuickRun -type syntax/rust
AutocmdFT rust let g:rustfmt_autosave = 1
AutocmdFT rust let g:rustfmt_command = system('which rustfmt')
AutocmdFT rust let g:rustfmt_options = "--write-mode=overwrite"
AutocmdFT rust let g:racer_cmd = system('which racer')

" -----------------------
" ---- Swift settings ----
" -----------------------
AutocmdFT swift let g:neomake_swift_swiftc_maker = {
                \ 'exe': 'swiftc',
                \ 'args': ['-parse'],
                \ 'errorformat': {
                \ '%E%f:%l:%c: error: %m,' .
                \ '%W%f:%l:%c: warning: %m,' .
                \ '%Z%\s%#^~%#,' .
                \ '%-G%.%#'
                \ },
                \ }
AutocmdFT swift let g:quickrun_config['swift'] = {
                \ 'command': 'xcrun',
                \ 'cmdopt': 'swift',
                \ 'exec': '%c %o %s',
                \}

" -----------------------
" ---- Ruby settings ----
" -----------------------
AutocmdFT ruby let g:rubycomplete_buffer_loading = 1
AutocmdFT ruby let g:rubycomplete_classes_in_global = 1
AutocmdFT ruby let g:rubycomplete_rails = 1
AutocmdFT ruby map <Leader>t :call RunCurrentSpecFile()<CR>
AutocmdFT ruby map <Leader>s :call RunNearestSpec()<CR>
AutocmdFT ruby map <Leader>l :call RunLastSpec()<CR>
AutocmdFT ruby map <Leader>a :call RunAllSpecs()<CR>
AutocmdFT ruby nnoremap <leader>rap  :RAddParameter<cr>
AutocmdFT ruby nnoremap <leader>rcpc :RConvertPostConditional<cr>
AutocmdFT ruby nnoremap <leader>rel  :RExtractLet<cr>
AutocmdFT ruby vnoremap <leader>rec  :RExtractConstant<cr>
AutocmdFT ruby vnoremap <leader>relv :RExtractLocalVariable<cr>
AutocmdFT ruby nnoremap <leader>rit  :RInlineTemp<cr>
AutocmdFT ruby vnoremap <leader>rrlv :RRenameLocalVariable<cr>
AutocmdFT ruby vnoremap <leader>rriv :RRenameInstanceVariable<cr>
AutocmdFT ruby vnoremap <leader>rem  :RExtractMethod<cr>

" -----------------------------
" ---- JavaScript settings ----
" -----------------------------
Autocmd BufWritePre *.js,*.jsx,*.coffee EsFix
Autocmd BufWritePre *.js,*.jsx,*.coffee Neoformat
AutocmdFT coffee,javascript,javascript.jsx,json let g:node_usejscomplete = 1
AutocmdFT coffee,javascript,javascript.jsx,json let g:tern_request_timeout = 1
AutocmdFT coffee,javascript,javascript.jsx,json let g:tern_show_signature_in_pum = '0'
AutocmdFT coffee,javascript,javascript.jsx,json let g:jsx_ext_required = 1        " ファイルタイプがjsxのとき読み込む．
AutocmdFT coffee,javascript,javascript.jsx,json let g:js_indent_typescript = 1
AutocmdFT coffee,javascript,javascript.jsx,json let g:tagbar_type_javascript = {'ctagsbin' : system('which jsctags')}
AutocmdFT coffee,javascript,javascript.jsx,json command! EsFix :call vimproc#system_bg("eslint --fix " . expand("%"))
Autocmd VimLeave *.js  !eslint_d stop

" -----------------------------
" ---- TypeScript settings ----
" -----------------------------
Autocmd BufWritePre *.ts EsFix
Autocmd BufWritePre *.ts Neoformat
AutocmdFT coffee,javascript,javascript.jsx,json command! EsFix :call vimproc#system_bg("eslint --fix " . expand("%"))
AutocmdFT typescript let g:neomake_typescript_tsc_maker = {
                \ 'args': [
                \ '--project', getcwd(), '--noEmit'
                \ ],
                \ 'append_file': 0,
                \ 'errorformat':
                \ '%E%f %#(%l\,%c): error %m,' .
                \ '%E%f %#(%l\,%c): %m,' .
                \ '%Eerror %m,' .
                \ '%C%\s%\+%m'
                \ }
Autocmd VimLeave *.ts  !eslint_d stop

" -----------------------
" ---- HTML settings ----
" -----------------------
AutocmdFT html,xhtml imap <buffer><expr><tab> emmet#isExpandable() ? "\<plug>(emmet-expand-abbr)" : "\<tab>"

" ---------------------------
" ---- Markdown settings ----
" ---------------------------
AutocmdFT md,markdown let g:previm_open_cmd = 'open -a Google\ Chrome'

" ------------------------
" ---- Other settings ----
" ------------------------
" ---- Enable Binary Mode
Autocmd BufReadPre  *.bin let &binary = 1
Autocmd BufReadPost * if &binary | silent %!xxd -g 1
Autocmd BufReadPost * set ft=xxd | endif
Autocmd BufWritePre * if &binary | %!xxd -r | endif
Autocmd BufWritePost * if &binary | silent %!xxd -g 1
Autocmd BufWritePost * set nomod | endif

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
" colorscheme spring-night
" colorscheme gotham256
" let g:lightline = { 'colorscheme': 'gotham256' }

let g:monokai_italic = 1
let g:monokai_thick_border = 1
" hi PmenuSel cterm=reverse ctermfg=33 ctermbg=222 gui=reverse guifg=#3399ff guibg=#f0e68c

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

" Tab補完
function! s:completion_check_bs()
    let l:col = col('.') - 1
    return !l:col || getline('.')[l:col - 1] =~? '\s'
endfunction

" Deoplete Key map
" inoremap <expr><silent><Tab> pumvisible() ? "\<C-n>" : (<sid>completion_check_bs() ? "\<Tab>" : deoplete#mappings#manual_complete())
" inoremap <expr><S-TAB>  pumvisible() ? "\<C-p>" : "\<C-h>"
" inoremap <expr> <CR> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
" inoremap <expr><C-h> deolete#mappings#smart_close_popup()."\<C-h>"
" inoremap <expr><BS> deoplete#mappings#smart_close_popup()."\<C-h>"
" " imap <expr><TAB> deoppet#expandable_or_jumpable() ? "\<Plug>(deoppet_expand_or_jump)" : pumvisible() ? "\<C-n>" : "\<TAB>"
" imap <expr><TAB> neosnippet#expandable_or_jumpable() ? "\<Plug>(neosnippet_expand_or_jump)" : pumvisible() ? "\<C-n>" : "\<TAB>"

" ---- Enable Filetype
filetype plugin indent on
filetype on
