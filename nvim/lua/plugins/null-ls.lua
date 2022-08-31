local status, null_ls = pcall(require, "null-ls")
if (not status) then
  error('null-ls is not intalled')
  return
end

local augroup_format = vim.api.nvim_create_augroup("Format", { clear = true })

null_ls.setup {
  sources = {
    null_ls.builtins.diagnostics.eslint_d.with({
      diagnostics_format = '[eslint] #{m}\n(#{c})'
    }),
    null_ls.builtins.diagnostics.fish,
    null_ls.builtins.diagnostics.eslint,
    null_ls.builtins.completion.spell,
    null_ls.builtins.formatting.stylua,
    null_ls.builtins.formatting.deno_fmt.with {
      condition = function(utils)
        return not (utils.has_file { ".prettierrc", ".prettierrc.js", "deno.json", "deno.jsonc" })
      end,
    },
    null_ls.builtins.formatting.prettier.with {
      condition = function(utils)
        return utils.has_file { ".prettierrc", ".prettierrc.js" }
      end,
      prefer_local = "node_modules/.bin",
    },
  },
  -- capabilities = common_config.capabilities,
  -- on_attach = function(client, bufnr)
  --   if client.server_capabilities.documentFormattingProvider then
  --     vim.api.nvim_clear_autocmds { buffer = 0, group = augroup_format }
  --     vim.api.nvim_create_autocmd("BufWritePre", {
  --       group = augroup_format,
  --       buffer = 0,
  --       callback = function() vim.lsp.buf.format() end
  --     })
  --   end
  -- end,
}
