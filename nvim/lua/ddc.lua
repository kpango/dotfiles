
local status, nvim_lsp = pcall(require, "lspconfig")
if (not status) then
  print("lspconfig is not installed")
  return
end

local status, navic = pcall(require, "nvim-navic")
if (not status) then
  print("navic is not installed")
  return
end

local servers = {
  'gopls',
  'clangd',
}

for _, lsp in ipairs(servers) do
  nvim_lsp[lsp].setup {
    flags = {
      debounce_text_changes = 150,
      },
    settings = {
      solargraph = {
        diagnostics = false
      }
    }
    on_attach = function(client, bufnr)
        navic.attach(client, bufnr)
        -- format on save
        if client.server_capabilities.documentFormattingProvider then
            vim.api.nvim_create_autocmd("BufWritePre", {
                group = vim.api.nvim_create_augroup("Format", { clear = true }),
                buffer = bufnr,
                callback = function() vim.lsp.buf.formatting_seq_sync() end
            })
        end
        vim.api.nvim_buf_set_option(bufnr,'omnifunc', 'v:lua.vim.lsp.omnifunc')
        local opts = { noremap=true, silent=true }
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gD', '<Cmd>lua vim.lsp.buf.declaration()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gd', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'K', '<Cmd>lua vim.lsp.buf.hover()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gi', '<Cmd>lua vim.lsp.buf.implementation()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-k>', '<Cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>wa', '<Cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>wr', '<Cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>wl', '<Cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>D', '<Cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>rn', '<Cmd>lua vim.lsp.buf.rename()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>ca', '<Cmd>lua vim.lsp.buf.code_action()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gr', '<Cmd>lua vim.lsp.buf.references()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>e', '<Cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '[d', '<Cmd>lua vim.lsp.diagnostic.goto_prev()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', ']d', '<Cmd>lua vim.lsp.diagnostic.goto_next()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>q', '<Cmd>lua vim.lsp.diagnostic.set_loclist()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, "n", "<space>f", "<Cmd>lua vim.lsp.buf.formatting()<CR>", opts)
    end
  }
end

local status, lsp_installer = pcall(require, "nvim-lsp-installer")
if (not status) then
  print("nvim-lsp-installer is not installed")
  return
end

lsp_installer.on_server_ready(function(server)
  local opts = {}
  server:setup(opts)
end)

local status, ddc = pcall(require, "ddc")
if (not status) then
  print("ddc is not installed")
  return
end

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
call ddc#enable()
]]
