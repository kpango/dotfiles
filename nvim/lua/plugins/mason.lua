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

-- mason_lspconfig.setup({
--     ensure_installed = all,
--     automatic_installation = false,
-- })

local status, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
if (not status) then
  error("cmp_nvim_lsp is not installed")
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
    capabilities = cmp_nvim_lsp.update_capabilities(vim.lsp.protocol.make_client_capabilities()),
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
        local opts = { noremap = true, silent = true, buffer = bufnr }
        vim.keymap.set('n', "<space>f", vim.lsp.buf.formatting, opts)
        vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
        vim.keymap.set('n', '<space>D', vim.lsp.buf.type_definition, opts)
        vim.keymap.set('n', '<space>ca', vim.lsp.buf.code_action, opts)
        vim.keymap.set('n', '<space>f', vim.lsp.buf.formatting, opts)
        vim.keymap.set('n', '<space>rn', vim.lsp.buf.rename, opts)
        vim.keymap.set('n', '<space>wa', vim.lsp.buf.add_workspace_folder, opts)
        vim.keymap.set('n', '<space>wr', vim.lsp.buf.remove_workspace_folder, opts)
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
        vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
        vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
        vim.keymap.set('n', 'grf', vim.lsp.buf.references, opts)
        vim.keymap.set('n', 'gs', vim.lsp.buf.signature_help, opts)
        vim.keymap.set('n', 'gtD', vim.lsp.buf.type_definition, opts)
        local opts = { noremap = true, silent = true}
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>e', '<cmd>lua vim.diagnostic.show_line_diagnostics()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '<space>q', '<cmd>lua vim.diagnostic.set_loclist()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', '[d', '<cmd>lua vim.diagnostic.goto_prev()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', ']d', '<cmd>lua vim.diagnostic.goto_next()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'g[', '<cmd>lua vim.diagnostic.goto_prev()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'g]', '<cmd>lua vim.diagnostic.goto_next()<CR>', opts)
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gx', '<cmd>lua vim.diagnostic.show_line_diagnostics()<CR>', opts)
        local status, navic = pcall(require, 'nvim-navic')
        if (not status) then
          error("navic is not installed")
          return
        end
        navic.attach(client, bufnr)
    end
  }
end })
