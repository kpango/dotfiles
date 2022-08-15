-- cnoreabbrev W! w!
-- cnoreabbrev Q! q!
-- cnoreabbrev Qall! qall!
-- cnoreabbrev Wq wq
-- cnoreabbrev Wa wa
-- cnoreabbrev wQ wq
-- cnoreabbrev WQ wq
-- cnoreabbrev W w
-- cnoreabbrev Q q
-- cnoreabbrev Qall qall
--
-- " Returnキーは常に新しい行を追加するように
-- nnoremap <CR> o<Esc>
--
-- " シェルのカーソル移動コマンドを有効化
-- cnoremap <C-a> <Home>
-- inoremap <C-a> <Home>
-- cnoremap <C-e> <End>
-- inoremap <C-e> <End>
-- cnoremap <C-f> <Right>
-- inoremap <C-f> <Right>
-- cnoremap <C-b> <Left>
-- inoremap <C-b> <Left>
--
-- " 折り返した行を複数行として移動
-- nnoremap <silent> j gj
-- nnoremap <silent> k gk
-- nnoremap <silent> gj j
-- nnoremap <silent> gk k
-- inoremap <silent> jj <Esc>
-- inoremap <silent> っj <ESC>
--
-- " ウィンドウの移動をCtrlキーと方向指定でできるように
-- nnoremap <C-h> <C-w>h
-- nnoremap <C-j> <C-w>j
-- nnoremap <C-k> <C-w>k
-- nnoremap <C-l> <C-w>l
--
-- inoremap <C-j> <Down>
-- inoremap <C-k> <Up>
-- inoremap <C-h> <Left>
-- inoremap <C-l> <Right>
--
-- " Esc2回で検索のハイライトを消す
-- nnoremap <silent> <Esc><Esc> :<C-u>nohlsearch<CR>
--
-- " gをバインドキーとしたtmuxと同じキーバインドでタブを操作
-- nnoremap <silent> gc :<C-u>tabnew<CR>
-- nnoremap <silent> gx :<C-u>tabclose<CR>
-- nnoremap gn gt
-- nnoremap gp gT
-- " g+oで現在開いている以外のタブを全て閉じる
-- nnoremap <silent> go :<C-u>tabonly<CR>
--
-- noremap ; :
-- inoremap <C-j> <esc>
-- inoremap <C-s> <esc>:w<CR>
-- nnoremap <C-q> :qall<CR>
--
-- inoremap { {}<LEFT>
-- inoremap [ []<LEFT>
-- inoremap ( ()<LEFT>
-- inoremap " ""<LEFT>
-- inoremap ' ''<LEFT>
-- let &t_SI = "\<Esc>]50;CursorShape=1\x7"
-- let &t_EI = "\<Esc>]50;CursorShape=0\x7"
-- inoremap <Esc> <Esc>lh
-- 等価
vim.api.nvim_set_keymap( 'n', 'j', 'gj', {noremap = true} )
vim.keymap.set( 'n', 'j', 'gj' )

-- 関数
vim.keymap.set('n', 'lhs', function() print("real lua function") end)
-- vim.keymap.set('n', 'asdf', require('jkl').my_fun)

-- 複数のモード
vim.keymap.set({'n', 'v'}, '<leader>lr', vim.lsp.buf.references, { buffer=true })

-- <Plug>
vim.keymap.set('n', '[%', '<Plug>(MatchitNormalMultiBackward)')
