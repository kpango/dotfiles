
local nvim_lsp = require('lspconfig')

local servers = {
  'gopls',
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
  }
end
