local M = {}

local function load_pass_secret(cmd, env_key)
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        local token = table.concat(data, "\n"):gsub("\n", "")
        vim.env[env_key] = token
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.notify("Error loading token for " .. env_key .. ": " .. table.concat(data, "\n"), vim.log.levels.ERROR)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("Command failed for " .. env_key .. " with exit code: " .. code, vim.log.levels.ERROR)
      end
    end,
  })
end

function M.load_token_from_pass()
  load_pass_secret("pass show ai/anthropic", "ANTHROPIC_API_KEY")
  load_pass_secret("pass show ai/groq", "GROQ_API_KEY")
  load_pass_secret("pass show ai/open_ai", "OPEN_AI_API_KEY")
end

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    M.load_token_from_pass()
  end,
})

return M

