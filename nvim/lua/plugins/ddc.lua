local status, mason = pcall(require, 'mason')
if (not status) then
  error("mason is not installed")
  return
end
mason.setup({
  ui = {
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗"
    }
  }
})

local status, mason_lspconfig = pcall(require, 'mason-lspconfig')
if (not status) then
  error("mason_lspconfig is not installed")
  return
end

local status, nvim_lsp = pcall(require, "lspconfig")
if (not status) then
  error("lspconfig is not installed")
  return
end

mason_lspconfig.setup_handlers({ function(server_name)
  local settings = {
      solargraph = {
        diagnostics = false
      }
  }
  if server_name == "sumneko_lua" then
      opts.settings = {
          Lua = {
              diagnostics = { globals = { 'vim' } },
          }
      }
  end
  nvim_lsp[server_name].setup{
    flags = {
      debounce_text_changes = 150,
    },
    settings = settings,
    on_attach = function(client, bufnr)
        -- format on save
        if client.server_capabilities.documentFormattingProvider then
            vim.api.nvim_create_autocmd("BufWritePre", {
                group = vim.api.nvim_create_augroup("Format", { clear = true }),
                buffer = bufnr,
                callback = function() vim.lsp.buf.format() end
            })
        end
        vim.api.nvim_buf_set_option(bufnr,'omnifunc', 'v:lua.vim.lsp.omnifunc')
        local opts = { noremap=true, silent=true }
        vim.api.nvim_buf_set_keymap(bufnr, 'n', "<space>f", vim.lsp.buf.formatting, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-k>', vim.lsp.buf.signature_help, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>D', vim.lsp.buf.type_definition, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>ca', vim.lsp.buf.code_action, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>e', vim.lsp.diagnostic.show_line_diagnostics, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>f', vim.lsp.buf.formatting, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>q', vim.lsp.diagnostic.set_loclist, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>rn', vim.lsp.buf.rename, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>wa', vim.lsp.buf.add_workspace_folder, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>wr', vim.lsp.buf.remove_workspace_folder, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'K', vim.lsp.buf.hover, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '[d', vim.lsp.diagnostic.goto_prev, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', ']d', vim.lsp.diagnostic.goto_next, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gD', vim.lsp.buf.declaration, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'g[', vim.lsp.diagnostic.goto_prev, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'g]', vim.lsp.diagnostic.goto_next, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gd', vim.lsp.buf.definition, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gtD', vim.lsp.buf.type_definition, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gi', vim.lsp.buf.implementation, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gr', vim.lsp.buf.references, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'grf', vim.lsp.buf.references, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gs', vim.lsp.buf.signature_help, opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gx', vim.lsp.diagnostic.show_line_diagnostics, opts)
        local status, navic = pcall(require, 'nvim-navic')
        if (not status) then
          error("navic is not installed")
          return
        end
        navic.attach(client, bufnr)
    end
  }
end })

vim.cmd[[
call ddc#custom#patch_global('sources', ['nvim-lsp', 'tabnine', 'deoppet', 'around', 'file'])
call ddc#custom#patch_global('sourceOptions', {
      \ '_': {
      \   'matchers': ['matcher_fuzzy', 'matcher_head'],
      \   'sorters': ['sorter_fuzzy', 'sorter_rank'],
      \   'converters': ['converter_fuzzy']
      \ },
      \ 'nvim-lsp': {
      \   'mark': 'lsp',
      \   'matchers': ['matcher_head'],
      \   'forceCompletionPattern': '\.\w*|:\w*|->\w*'
      \ },
      \ 'tabnine': {
      \   'mark': 'TN',
      \   'maxCandidates': 5,
      \   'isVolatile': v:true,
      \ },
      \ 'deoppet': {'dup': v:true, 'mark': 'dp'},
      \ 'around': {'mark': 'A'},
      \ 'file': {
      \   'mark': 'file',
      \   'isVolatile': v:true,
      \   'forceCompletionPattern': '\S/\S*|\.\w*|:\w*|->\w*'
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
nnoremap :       <Cmd>call CommandlinePre()<CR>:

function! CommandlinePre() abort
  " Note: It disables default command line completion!
  cnoremap <expr> <Tab>
  \ pum#visible() ? '<Cmd>call pum#map#insert_relative(+1)<CR>' :
  \ ddc#manual_complete()
  cnoremap <S-Tab> <Cmd>call pum#map#insert_relative(-1)<CR>
  cnoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
  cnoremap <C-e>   <Cmd>call pum#map#cancel()<CR>

  " Overwrite sources
  if !exists('b:prev_buffer_config')
    let b:prev_buffer_config = ddc#custom#get_buffer()
  endif
  call ddc#custom#patch_buffer('sources',
          \ ['cmdline', 'cmdline-history', 'around'])

  autocmd User DDCCmdlineLeave ++once call CommandlinePost()
  autocmd InsertEnter <buffer> ++once call CommandlinePost()

  " Enable command line completion
  call ddc#enable_cmdline_completion()
endfunction

function! CommandlinePost() abort
  cunmap <Tab>
  cunmap <S-Tab>
  cunmap <C-y>
  cunmap <C-e>

  " Restore sources
  if exists('b:prev_buffer_config')
    call ddc#custom#set_buffer(b:prev_buffer_config)
    unlet b:prev_buffer_config
  else
    call ddc#custom#set_buffer({})
  endif
endfunction

call ddc#enable()
]]
