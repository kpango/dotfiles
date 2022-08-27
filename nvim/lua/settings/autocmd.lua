local autocmd = vim.api.nvim_create_autocmd
local augroup = function(name)
    return vim.api.nvim_create_augroup(name, { clear = true })
end

vim.cmd([[
  augroup AutoGroup
      autocmd!
  augroup END

  command! -nargs=* Autocmd autocmd AutoGroup <args>
  command! -nargs=* AutocmdFT autocmd AutoGroup FileType <args>
]])

-- Update plugins on change in the plugin definitions file
autocmd({ 'BufWritePost' }, {
    desc = 'Auto update packer plugins once the plugins definition file is changed',
    pattern = 'plugins.lua',
    command = 'source <afile> | PackerSync',
    group = augroup('PackerUserConfig'),
})

local cmp_load_group = augroup('CustomCMPLoad')

autocmd({ 'FileType' }, {
    desc = 'Load auto completion for crates only when a toml file is open',
    pattern = 'toml',
    callback = function()
        require('cmp').setup.buffer({ sources = { { name = 'crates' } } })
    end,
    group = cmp_load_group,
})
autocmd({ 'FileType' }, {
    desc = 'Load auto completion using the buffer only for md files',
    pattern = 'markdown',
    callback = function()
        require('cmp').setup.buffer({ sources = { { name = 'buffer' } } })
    end,
    group = cmp_load_group,
})

autocmd({ 'ModeChanged' }, {
    desc = 'Stop snippets when you leave to normal mode',
    pattern = '*',
    callback = function()
        if ((vim.v.event.old_mode == 's' and vim.v.event.new_mode == 'n') or vim.v.event.old_mode == 'i')
            and require('luasnip').session.current_nodes[vim.api.nvim_get_current_buf()]
            and not require('luasnip').session.jump_active
        then
            require('luasnip').unlink_current()
        end
    end,
})

autocmd({ 'CursorHold', 'CursorHoldI' }, {
    desc = 'Show box with diagnosticis for current line',
    pattern = '*',
    callback = function()
        vim.diagnostic.open_float({ focusable = false })
    end,
})

autocmd({ 'BufRead' }, {
    desc = "Prevent accidental writes to buffers that shouldn't be edited",
    pattern = '*.orig',
    command = 'set readonly',
})

local paste_mode_group = augroup('PasteMode')
autocmd({ 'InsertLeave' }, {
    desc = 'Leave paste mode when leaving insert mode',
    pattern = '*',
    command = 'set nopaste',
    group = paste_mode_group,
})

autocmd({ 'BufRead' }, {
    desc = 'Help markdown filetype detection',
    pattern = '*.md',
    command = 'set filetype=markdown',
})

autocmd({ 'TextYankPost' }, {
    desc = 'Highlight yanked text',
    pattern = '*',
    callback = function()
        require('vim.highlight').on_yank({ higroup = 'IncSearch', timeout = 1000 })
    end,
})

autocmd({ 'BufWipeout' }, {
    desc = 'Auto close NvimTree when a file is opened',
    pattern = 'NvimTree_*',
    callback = function()
        vim.schedule(function()
            require('bufferline.state').set_offset(0)
        end)
    end,
})

autocmd({ 'BufReadPost' }, {
    desc = 'Make files readonly when outside of current working dir',
    pattern = '*',
    callback = function()
        if string.sub(vim.api.nvim_buf_get_name(0), 1, string.len(vim.fn.getcwd())) ~= vim.fn.getcwd() then
            vim.bo.readonly = true
            vim.bo.modifiable = false
        end
    end,
})

local spaces_highlight_group = augroup('SpacesHighlightGroup')
autocmd({ 'VimEnter', 'WinNew' }, {
    desc = 'Highlight all tabs and trailing whitespaces',
    pattern = '*',
    group = spaces_highlight_group,
    callback = function()
        vim.fn.matchadd('ExtraWhitespace', '\\s\\+$\\|\\t')
    end,
})

autocmd({ 'FileType' }, {
    desc = 'Remove spaces highlights in selected filetypes',
    pattern = 'help,toggleterm',
    group = spaces_highlight_group,
    callback = function()
        for _, match in ipairs(vim.fn.getmatches()) do
            if match['group'] == 'ExtraWhitespace' then
                vim.fn.matchdelete(match['id'])
            end
        end
    end,
})

autocmd({ 'BufWinEnter' }, {
    desc = 'Remove spaces highlights in selected filetypes',
    pattern = '*.txt',
    group = spaces_highlight_group,
    callback = function(event)
        for _, match in ipairs(vim.fn.getmatches()) do
            if match['group'] == 'ExtraWhitespace' then
                vim.fn.matchdelete(match['id'])
            end
        end
    end,
})
