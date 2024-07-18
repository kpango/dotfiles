local autocmd = vim.api.nvim_create_autocmd
local usercmd = vim.api.nvim_create_user_command
local augroup = function(name)
	return vim.api.nvim_create_augroup(name, { clear = true })
end

local auto_group = augroup("AutoGroup")
usercmd("Autocmd", function(opts)
	autocmd(opts.args, { group = auto_group })
end, { nargs = "*" })
usercmd("AutocmdFT", function(opts)
	autocmd("FileType", {
		group = auto_group,
		pattern = opts.args,
	})
end, { nargs = "*" })

-- local cmp_load_group = augroup('CustomCMPLoad')
--
-- autocmd({ 'FileType' }, {
--     desc = 'Load auto completion for crates only when a toml file is open',
--     pattern = 'toml',
--     callback = function()
--         safe_require('cmp').setup.buffer({ sources = { { name = 'crates' } } })
--     end,
--     group = cmp_load_group,
-- })

-- autocmd({ 'FileType' }, {
--     desc = 'Load auto completion using the buffer only for md files',
--     pattern = 'markdown',
--     callback = function()
--         safe_require('cmp').setup.buffer({ sources = { { name = 'buffer' } } })
--     end,
--     group = cmp_load_group,
-- })

-- autocmd({ 'ModeChanged' }, {
--     desc = 'Stop snippets when you leave to normal mode',
--     pattern = '*',
--     callback = function()
--         local luasnip = safe_require('luasnip')
--         if ((vim.v.event.old_mode == 's' and vim.v.event.new_mode == 'n') or vim.v.event.old_mode == 'i')
--             and luasnip.session.current_nodes[vim.api.nvim_get_current_buf()]
--             and not luasnip.session.jump_active
--         then
--             luasnip.unlink_current()
--         end
--     end,
-- })

autocmd({ "CursorHold", "CursorHoldI" }, {
	desc = "Show box with diagnosticis for current line",
	pattern = "*",
	callback = function()
		vim.diagnostic.open_float({ focusable = false })
	end,
})

autocmd({ "BufRead" }, {
	desc = "Prevent accidental writes to buffers that shouldn't be edited",
	pattern = "*.orig",
	command = "set readonly",
})

local paste_mode_group = augroup("PasteMode")
autocmd({ "InsertLeave" }, {
	desc = "Leave paste mode when leaving insert mode",
	pattern = "*",
	command = "set nopaste",
	group = paste_mode_group,
})

autocmd({ "BufRead" }, {
	desc = "Help markdown filetype detection",
	pattern = "*.md",
	command = "set filetype=markdown",
})

autocmd({ "TextYankPost" }, {
	desc = "Highlight yanked text",
	pattern = "*",
	callback = function()
		safe_require("vim.highlight").on_yank({ higroup = "IncSearch", timeout = 1000 })
	end,
})

autocmd({ "BufWipeout" }, {
	desc = "Auto close NvimTree when a file is opened",
	pattern = "NvimTree_*",
	callback = function()
		vim.schedule(function()
			safe_require("bufferline.state").set_offset(0)
		end)
	end,
})

local spaces_highlight_group = augroup("SpacesHighlightGroup")
autocmd({ "VimEnter", "WinNew" }, {
	desc = "Highlight all tabs and trailing whitespaces",
	pattern = "*",
	group = spaces_highlight_group,
	callback = function()
		vim.fn.matchadd("ExtraWhitespace", "\\s\\+$\\|\\t")
	end,
})

autocmd({ "FileType" }, {
	desc = "Remove spaces highlights in selected filetypes",
	pattern = "help,toggleterm",
	group = spaces_highlight_group,
	callback = function()
		for _, match in ipairs(vim.fn.getmatches()) do
			if match["group"] == "ExtraWhitespace" then
				vim.fn.matchdelete(match["id"])
			end
		end
	end,
})

autocmd({ "BufWinEnter" }, {
	desc = "Remove spaces highlights in selected filetypes",
	pattern = "*.txt",
	group = spaces_highlight_group,
	callback = function(event)
		for _, match in ipairs(vim.fn.getmatches()) do
			if match["group"] == "ExtraWhitespace" then
				vim.fn.matchdelete(match["id"])
			end
		end
	end,
})
