local M = {}

function M.load_token_from_pass()
  local anthropic_token = vim.fn.system("pass show ai/anthropic | tr -d '\n'")
  vim.env.ANTHROPIC_API_KEY = anthropic_token
  local groq_token = vim.fn.system("pass show ai/groq | tr -d '\n'")
  vim.env.GROQ_API_KEY = groq_token
  local open_ai_token = vim.fn.system("pass show ai/open_ai | tr -d '\n'")
  vim.env.OPEN_AI_API_KEY = open_ai_token
end

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    M.load_token_from_pass()
  end,
})

return M
