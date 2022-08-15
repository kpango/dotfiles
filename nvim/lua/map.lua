-- 等価
vim.api.nvim_set_keymap( 'n', 'j', 'gj', {noremap = true} )
vim.keymap.set( 'n', 'j', 'gj' )

-- 関数
vim.keymap.set('n', 'lhs', function() print("real lua function") end)
vim.keymap.set('n', 'asdf', require('jkl').my_fun)

-- 複数のモード
vim.keymap.set({'n', 'v'}, '<leader>lr', vim.lsp.buf.references, { buffer=true })

-- <Plug>
vim.keymap.set('n', '[%', '<Plug>(MatchitNormalMultiBackward)')
