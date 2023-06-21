local status, filetype = pcall(require, 'filetype')
if (not status) then
  error("filetype is not installed")
  return
end
filetype.setup({
    overrides = {
        extensions = {},
        literal = {},
        complex = {
            [".*git/config"] = "gitconfig", -- Included in the plugin
        },
        function_extensions = {
            ["cpp"] = function()
                vim.bo.filetype = "cpp"
                vim.bo.cinoptions = vim.bo.cinoptions .. "L0"
            end,
            ["pdf"] = function()
                vim.bo.filetype = "pdf"
                vim.fn.jobstart(
                    "open -a skim " .. '"' .. vim.fn.expand("%") .. '"'
                )
            end,
        },
        function_literal = {
            Brewfile = function()
                vim.cmd("syntax off")
            end,
        },
        function_complex = {
            ["*.math_notes/%w+"] = function()
                vim.cmd("iabbrev $ $$")
            end,
        },
        shebang = {
            dash = "sh",
        },
    },
})
