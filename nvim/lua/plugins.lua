-- Initialize necessary paths

local fn = vim.fn
local pkg_path = fn.stdpath("config") .. "/lazy"
local lazypath = pkg_path .. "/lazy.nvim"

-- Auto-install lazy.nvim if not already installed
if not vim.loop.fs_stat(lazypath) then
	fn.system({
		"git",
		"clone",
		"--depth",
		"1",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim",
		lazypath,
	})
end

vim.opt.rtp:prepend(lazypath)
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "preview" }
vim.opt.shortmess:append("c")

local function safe_require(module_name)
	local status, module = pcall(require, module_name)
	if not status then
		vim.api.nvim_err_writeln("Error loading module: " .. module_name .. " is not installed. Install path: " .. pkg_path)
		return nil
	end
	return module
end

local languages = {
	"bash",
	"c",
	"cpp",
	"dart",
	"dockerfile",
	"go",
	"html",
	"json",
	"lua",
	"make",
	"markdown",
	"nim",
	"rust",
	"yaml",
	"zig",
}

local lsps = {
	"clangd",
	"dockerls",
	"gopls",
	"lua_ls",
	"nim_langserver",
	"pyright",
	"rust_analyzer",
	"zls",
}

local tools = {
	"delve",
	"gofumpt",
	"golancci-lint",
	"golines",
	"gomodifytags",
	"hadolint",
	"snyk",
	"trivy",
}

safe_require("lazy").setup({
	-- General plugins
	{
		"hrsh7th/nvim-cmp",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = {
			{
				"neovim/nvim-lspconfig",
				event = "BufReadPre",
				dependencies = {
					"williamboman/mason.nvim",
					"williamboman/mason-lspconfig.nvim",
					{
						"ray-x/go.nvim",
						ft = { "go" },
						config = true,
						opts = {
							gofmt = "gofumpt",
							goimports = "strictgoimports",
							lsp_cfg = false,
						},
					},
					{ "hrsh7th/cmp-nvim-lsp", event = { "InsertEnter", "BufReadPre" } },
				},
				config = function()
					local servers = {
						gopls = safe_require("go.lsp").config(),
						rust_analyzer = {
							settings = {
								["rust-analyzer"] = {
									cargo = {
										allFeatures = true,
									},
									checkOnSave = {
										command = "clippy",
									},
								},
							},
						},
						clangd = {},
						dockerls = {},
						lua_ls = { -- or "sumneko_lua"
							settings = {
								Lua = {
									runtime = {
										version = "LuaJIT",
										path = vim.split(package.path, ";"),
									},
									diagnostics = {
										globals = { "vim" },
									},
									workspace = {
										library = vim.api.nvim_get_runtime_file("", true),
										checkThirdParty = false,
									},
									telemetry = {
										enable = false,
									},
								},
							},
						},
						nimls = {},
						pyright = {
							settings = {
								python = {
									analysis = {
										typeCheckingMode = "strict",
									},
								},
							},
						},
						zls = {},
					}

					local default_config = {
						on_attach = function(client, bufnr)
							vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
							if client.server_capabilities.document_highlight then
								vim.api.nvim_create_augroup("lsp_document_highlight", { clear = false })
								vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
									group = "lsp_document_highlight",
									buffer = bufnr,
									callback = vim.lsp.buf.document_highlight,
								})
								vim.api.nvim_create_autocmd("CursorMoved", {
									group = "lsp_document_highlight",
									buffer = bufnr,
									callback = vim.lsp.buf.clear_references,
								})
							end
						end,
						flags = {
							debounce_text_changes = 150,
						},
						capabilities = safe_require("cmp_nvim_lsp").default_capabilities(
							vim.lsp.protocol.make_client_capabilities()
						),
					}
					safe_require("mason").setup({
						ui = {
							icons = {
								package_installed = "✓",
								package_pending = "➜",
								package_uninstalled = "✗",
							},
						},
					})
					safe_require("mason-lspconfig").setup({
						ensure_installed = lsps,
					})

					local lspconfig = safe_require("lspconfig")
					for _, server_name in ipairs(lsps) do
						lspconfig[server_name].setup(vim.tbl_deep_extend("force", default_config, servers[server_name] or {}))
					end
				end,
			},
			{
				"L3MON4D3/LuaSnip",
				build = "make install_jsregexp",
				event = "InsertEnter",
				config = function()
					safe_require("luasnip").config.set_config({
						history = true,
						updateevents = "TextChanged,TextChangedI",
					})
					safe_require("luasnip.loaders.from_vscode").lazy_load()
				end,
			},
			{ "hrsh7th/cmp-buffer", event = "InsertEnter" },
			{ "hrsh7th/cmp-calc", event = "InsertEnter" },
			{ "hrsh7th/cmp-cmdline", event = "ModeChanged" },
			{ "hrsh7th/cmp-nvim-lsp-document-symbol", event = "InsertEnter" },
			{ "hrsh7th/cmp-nvim-lsp-signature-help", event = "InsertEnter" },
			{ "hrsh7th/cmp-nvim-lua", event = "InsertEnter" },
			{ "hrsh7th/cmp-path", event = "InsertEnter" },
			{ "ray-x/cmp-treesitter", event = "InsertEnter" },
			{
				"petertriho/cmp-git",
				config = true,
				event = "InsertEnter",
				dependencies = { "nvim-lua/plenary.nvim" },
			},
			{ "octaltree/cmp-look", event = "InsertEnter" },
			{ "onsails/lspkind.nvim", event = "InsertEnter" },
			{ "rafamadriz/friendly-snippets", event = "InsertEnter" },
			{ "saadparwaiz1/cmp_luasnip", event = "InsertEnter" },
		},
		config = function()
			local cmp = safe_require("cmp")
			local luasnip = safe_require("luasnip")
			local lspkind = safe_require("lspkind")
			local has_words_before = function()
				if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then
					return false
				end
				local line, col = unpack(vim.api.nvim_win_get_cursor(0))
				return col ~= 0 and vim.api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]:match("^%s*$") == nil
			end

			local check_backspace = function()
				local col = vim.fn.col(".") - 1
				return col == 0 or vim.fn.getline("."):sub(col, col):match("%s")
			end
			cmp.setup({
				flags = {
					debounce_text_changes = 150,
				},
				snippet = {
					expand = function(args)
						luasnip.lsp_expand(args.body)
					end,
				},
				mapping = {
					["<C-p>"] = cmp.mapping.select_prev_item(),
					["<C-n>"] = cmp.mapping.select_next_item(),
					["<C-b>"] = cmp.mapping(cmp.mapping.scroll_docs(-1), { "i", "c" }),
					["<C-f>"] = cmp.mapping(cmp.mapping.scroll_docs(1), { "i", "c" }),
					["<C-Space>"] = cmp.mapping(cmp.mapping.complete(), { "i", "c" }),
					["<C-y>"] = cmp.mapping.confirm({ select = true }),
					["<C-e>"] = cmp.mapping({
						i = cmp.mapping.abort(),
						c = cmp.mapping.close(),
					}),
					["<CR>"] = cmp.mapping.confirm({ select = true }),
					["<Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() and has_words_before() then
							cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
						elseif safe_require("copilot.suggestion").is_visible() then
							safe_require("copilot.suggestion").accept()
						elseif luasnip.expandable() then
							luasnip.expand()
						elseif luasnip.expand_or_jumpable() then
							luasnip.expand_or_jump()
						elseif check_backspace() then
							fallback()
						else
							fallback()
						end
					end, {
						"i",
						"s",
					}),
					["<S-Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() and has_words_before() then
							cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
						elseif luasnip.jumpable(-1) then
							luasnip.jump(-1)
						else
							fallback()
						end
					end, {
						"i",
						"s",
					}),
				},
				sources = cmp.config.sources({
					-- Copilot Source
					{ name = "copilot", group_index = 2 },
					{ name = "copilot_cmp", group_index = 2 },
					-- Other Sources
					{ name = "nvim_lsp", group_index = 2 },
					{ name = "nvim_lsp_signature_help" },
					{ name = "luasnip", group_index = 2 },
					{ name = "buffer", get_bufnrs = vim.api.nvim_list_bufs, group_index = 2 },
					{ name = "look", group_index = 2 },
					{ name = "path", group_index = 2 },
					{ name = "cmdline" },
					{ name = "git" },
				}),
				sorting = {
					priority_weight = 2,
					comparators = {
						safe_require("copilot_cmp.comparators").prioritize,
						-- Below is the default comparitor list and order for nvim-cmp
						cmp.config.compare.offset,
						-- cmp.config.compare.scopes, --this is commented in nvim-cmp too
						cmp.config.compare.exact,
						cmp.config.compare.score,
						cmp.config.compare.recently_used,
						cmp.config.compare.locality,
						cmp.config.compare.kind,
						cmp.config.compare.sort_text,
						cmp.config.compare.length,
						cmp.config.compare.order,
					},
				},
				window = {
					completion = cmp.config.window.bordered({
						border = "single",
						col_offset = -3,
						side_padding = 0,
					}),
					documentation = cmp.config.window.bordered({
						winhiglight = "NormalFloat:CompeDocumentation,FloatBorder:TelescopeBorder",
					}),
				},
				formatting = {
					format = lspkind.cmp_format({
						mode = "symbol_text",
						preset = "codicons",
						-- with_text = false,
						maxwidth = 50,
						ellipsis_char = "...",
						menu = {
							copilot = "[COP]",
							nvim_lua = "[LUA]",
							nvim_lsp = "[LSP]",
							cmp_tabnine = "[TN]",
							luasnip = "[LSN]",
							buffer = "[Buf]",
							path = "[PH]",
							look = "[LK]",
						},
						symbol_map = {
							Array = "",
							Boolean = "",
							Class = " ",
							Color = " ",
							Constant = " ",
							Constructor = " ",
							Copilot = "",
							Enum = " ",
							EnumMember = " ",
							Event = " ",
							Field = " ",
							File = " ",
							Folder = " ",
							Function = " ",
							Interface = " ",
							Key = "",
							Keyword = " ",
							Method = " ",
							Module = " ",
							Namespace = "",
							Null = "",
							Number = "",
							Object = "",
							Operator = " ",
							Package = "",
							Property = " ",
							Reference = " ",
							Snippet = " ",
							String = "",
							Struct = " ",
							Text = " ",
							TypeParameter = " ",
							Unit = " ",
							Value = " ",
							Variable = " ",
						},
					}),
				},
				keys = {
					{
						"gD",
						vim.lsp.buf.declaration,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"gd",
						vim.lsp.buf.definition,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"gr",
						vim.lsp.buf.references,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"gi",
						vim.lsp.buf.implementation,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"K",
						vim.lsp.buf.hover,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<C-k>",
						vim.lsp.buf.signature_help,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>wa",
						vim.lsp.buf.add_workspace_folder,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>wr",
						vim.lsp.buf.remove_workspace_folder,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>wl",
						function()
							print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
						end,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>D",
						vim.lsp.buf.type_definition,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>rn",
						vim.lsp.buf.rename,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>ca",
						vim.lsp.buf.code_action,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>f",
						function()
							vim.lsp.buf.format({ async = true })
						end,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>e",
						vim.diagnostic.show_line_diagnostics,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"<space>q",
						vim.diagnostic.set_loclist,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"[d",
						vim.diagnostic.goto_prev,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
					{
						"]d",
						vim.diagnostic.goto_next,
						mode = "n",
						desc = "",
						noremap = true,
						silent = true,
					},
				},
				experimental = {
					ghost_text = false,
					native_menu = false,
				},
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		run = ":TSUpdate",
		event = "BufReadPost",
		dependencies = {
			"nvim-treesitter/nvim-treesitter-textobjects",
			{ "navarasu/onedark.nvim", config = true, opts = { style = "darker" } },
		},
		config = function()
			safe_require("nvim-treesitter.configs").setup({
				auto_install = true,
				sync_install = false,
				ensure_installed = languages,
				highlight = {
					enable = true,
				},
				indent = {
					enable = true,
				},
				autotag = {
					enable = true,
				},
			})
		end,
	},
	{
		"zbirenbaum/copilot-cmp",
		after = { "copilot.lua", "nvim-cmp" },
		event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
		fix_pairs = true,
		config = true,
		dependencies = {
			"zbirenbaum/copilot.lua",
			event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
			config = function()
				safe_require("copilot").setup({
					panel = {
						enabled = false,
						auto_refresh = true,
						keymap = {
							jump_prev = "[[",
							jump_next = "]]",
							accept = "<CR>",
							refresh = "gr",
							open = "<M-CR>",
						},
						layout = {
							position = "bottom", -- | top | left | right
							ratio = 0.4,
						},
					},
					suggestion = {
						enabled = false,
						auto_trigger = true,
						debounce = 75,
						keymap = {
							accept = false,
							accept_word = false,
							accept_line = false,
							next = "<M-]>",
							prev = "<M-[>",
							dismiss = "<C-]>",
						},
					},
					filetypes = {
						yaml = false,
						markdown = false,
						help = false,
						gitcommit = false,
						gitrebase = false,
						hgcommit = false,
						svn = false,
						cvs = false,
						["."] = false,
					},
					copilot_node_command = "node", -- Node.js version must be > 16.x
					server_opts_overrides = {
						autostart = true, -- Ensure Copilot autostarts
					},
					on_status_update = safe_require("lualine").refresh,
				})
			end,
		},
	},
	{
		"numToStr/Comment.nvim",
		event = "BufReadPost",
		config = true,
		lazy = true,
		opts = {
			ignore = "^$",
		},
		keys = {
			{
				"<C-c>",
				function()
					safe_require("Comment.api").toggle.linewise.current()
				end,
				desc = "",
				mode = "n",
				noremap = true,
				silent = true,
			},
			{
				"<C-c>",
				function()
					safe_require("Comment.api").toggle.linewise(fn.visualmode())
				end,
				desc = "",
				mode = "x",
				noremap = true,
				silent = true,
			},
			{
				"<C-c>",
				function()
					safe_require("Comment.api").toggle.linewise.current()
				end,
				desc = "",
				mode = "i",
				noremap = true,
				silent = true,
			},
		},
	},
	{
		"nvim-lualine/lualine.nvim",
		event = "VimEnter",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
			"SmiteshP/nvim-navic",
		},
		opts = {
			options = {
				icons_enabled = true,
				theme = "palenight",
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
				disabled_filetypes = { "NvimTree", "lazy", "TelescopePrompt" },
				always_divide_middle = true,
				globalstatuses = true,
				globalstatus = true,
				colored = false,
			},
			sections = {
				lualine_a = { "mode" },
				lualine_b = {
					"branch",
					"diff",
					{
						"diagnostics",
						sources = { "nvim_lsp", "coc" },
						update_in_insert = true,
						always_visible = true,
					},
				},
				lualine_c = {
					{
						"filename",
						path = 1,
						file_status = true,
						shorting_target = 40,
						symbols = {
							modified = "[+]",
							readonly = "[RO]",
							unnamed = "Untitled",
						},
					},
					function()
						local navic = safe_require("nvim-navic")
						return {
							function()
								return navic.get_location()
							end,
							cond = function()
								return navic.is_available()
							end,
						}
					end,
				},
				lualine_x = {
					{
						"diagnostics",
						sources = { "nvim_diagnostic" },
						symbols = {
							error = " ",
							warn = " ",
							info = " ",
							hint = " ",
						},
					},
					"encoding",
					"filetype",
				},
				lualine_y = {
					{ "diagnostics", source = { "nvim-lsp" } },
					{ "progress" },
				},
				lualine_z = { "location" },
			},
			inactive_sections = {
				lualine_a = {},
				lualine_b = {},
				lualine_c = {
					{
						"filename",
						path = 2,
						file_status = true,
						shorting_target = 40,
						symbols = {
							modified = " [+]",
							readonly = " [RO]",
							unnamed = "Untitled",
						},
					},
				},
				lualine_x = { "filetype" },
				lualine_y = { "%p%%", "location" },
				lualine_z = {},
			},
			tabline = {},
			extensions = { "fugitive", "fzf", "nvim-tree" },
		},
		dependencies = "nvim-tree/nvim-web-devicons",
		config = true,
	},
	{
		"mvllow/modes.nvim",
		config = true,
		opts = {
			colors = {
				copy = "#FFEE55",
				delete = "#DC669B",
				insert = "#55AAEE",
				visual = "#DD5522",
			},
		},
	},
	{
		"nathom/filetype.nvim",
		lazy = false,
		config = true,
		opts = {
			overrides = {
				extensions = {},
				literal = {},
				complex = {
					[".*git/config"] = "gitconfig",
				},
				function_extensions = {
					["cpp"] = function()
						vim.bo.filetype = "cpp"
						vim.bo.cinoptions = vim.bo.cinoptions .. "L0"
					end,
					["pdf"] = function()
						vim.bo.filetype = "pdf"
						fn.jobstart("open -a skim " .. '"' .. fn.expand("%") .. '"')
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
		},
	},
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = "nvim-tree/nvim-web-devicons",
		config = true,
		opts = {
			options = {
				mode = "tabs",
				separator_style = "slant",
				always_show_bufferline = false,
				show_buffer_close_icons = false,
				show_close_icon = false,
				color_icons = true,
			},
			highlights = {
				separator = {
					fg = "#073642",
					bg = "#002b36",
				},
				separator_selected = {
					fg = "#073642",
				},
				background = {
					fg = "#657b83",
					bg = "#002b36",
				},
				buffer_selected = {
					fg = "#fdf6e3",
				},
				fill = {
					bg = "#073642",
				},
			},
		},
	},
	{
		"windwp/nvim-autopairs",
		opts = {
			disable_filetype = { "TelescopePrompt", "vim" },
		},
		config = true,
	},
	{
		"lewis6991/gitsigns.nvim",
		event = "BufReadPost",
		config = true,
		opts = {
			signs = {
				add = { text = "┃" },
				change = { text = "┃" },
				delete = { text = "_" },
				topdelete = { text = "‾" },
				changedelete = { text = "~" },
				untracked = { text = "┆" },
			},
			signcolumn = true, -- Toggle with :Gitsigns toggle_signs
			numhl = false, -- Toggle with :Gitsigns toggle_numhl
			linehl = false, -- Toggle with :Gitsigns toggle_linehl
			word_diff = false, -- Toggle with :Gitsigns toggle_word_diff
			watch_gitdir = {
				interval = 1000,
				follow_files = true,
			},
			attach_to_untracked = true,
			current_line_blame = false, -- Toggle with :Gitsigns toggle_current_line_blame
			current_line_blame_opts = {
				virt_text = true,
				virt_text_pos = "eol", -- 'eol' | 'overlay' | 'right_align'
				delay = 1000,
				ignore_whitespace = false,
			},
			current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
			sign_priority = 6,
			update_debounce = 100,
			status_formatter = nil, -- Use default
			max_file_length = 40000, -- Disable if file is longer than this (in lines)
			preview_config = {
				-- Options passed to nvim_open_win
				border = "single",
				style = "minimal",
				relative = "cursor",
				row = 0,
				col = 1,
			},
		},
		keys = function(gs, keys)
			return {
				{
					"]c",
					function()
						if vim.wo.diff then
							return "]c"
						end
						vim.schedule(function()
							gs.next_hunk()
						end)
						return "<Ignore>"
					end,
					desc = "",
					mode = "n",
					expr = true,
				},
				{
					"[c",
					function()
						if vim.wo.diff then
							return "[c"
						end
						vim.schedule(function()
							gs.prev_hunk()
						end)
						return "<Ignore>"
					end,
					desc = "",
					mode = "n",
					expr = true,
				},
				{
					"<leader>hs",
					"<Cmd>Gitsigns stage_hunk<CR>",
					desc = "",
					mode = { "n", "v" },
					silent = true,
					noremap = true,
				},
				{
					"<leader>hr",
					"<Cmd>Gitsigns reset_hunk<CR>",
					desc = "",
					mode = { "n", "v" },
					silent = true,
					noremap = true,
				},
				{
					"<leader>hS",
					gs.stage_buffer,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"<leader>hR",
					gs.reset_buffer,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"<leader>hu",
					gs.undo_stage_hunk,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"<leader>hp",
					gs.preview_hunk,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"<leader>hb",
					function()
						gs.blame_line({ full = true })
					end,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"<leader>hd",
					gs.diffthis,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"<leader>hD",
					function()
						gs.diffthis("~")
					end,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"<leader>tb",
					gs.toggle_current_line_blame,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"<leader>td",
					gs.toggle_deleted,
					desc = "",
					mode = "n",
					silent = true,
					noremap = true,
				},
				{
					"ih",
					"<Cmd>Gitsigns select_hunk<CR>",
					desc = "",
					mode = { "o", "x" },
					silent = true,
					noremap = true,
				},
			}
		end,
	},
	{
		"nvim-telescope/telescope.nvim",
		cmd = "Telescope",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			local telescope = safe_require("telescope")
			telescope.setup({
				defaults = {
					mappings = {
						i = {
							["<C-n>"] = safe_require("telescope.actions").move_selection_next,
							["<C-p>"] = safe_require("telescope.actions").move_selection_previous,
						},
					},
				},
			})
		end,
	},
	-- code formatter setting
	{
		"mhartington/formatter.nvim",
		event = "BufWritePost",
		config = function()
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = vim.api.nvim_create_augroup("FormatAutogroup", { clear = true }),
				pattern = "*",
				command = "FormatWrite",
			})

			-- フォーマッタの設定
			safe_require("formatter").setup({
				logging = false,
				filetype = {
					lua = {
						function()
							return {
								exe = "stylua",
								args = { "--stdin-filepath", vim.fn.fnameescape(vim.api.nvim_buf_get_name(0)), "--", "-" },
								stdin = true,
							}
						end,
					},
					go = {
						function()
							return {
								exe = "golines",
								args = { "-w", "--max-len=200", "--base-formatter=gofumpt" },
								stdin = true,
							}
						end,
						function()
							return {
								exe = "gofumpt",
								args = { "-w" },
								stdin = true,
							}
						end,
						function()
							return {
								exe = "strictgoimports",
								args = { "-w" },
								stdin = true,
							}
						end,
						function()
							return {
								exe = "goimports",
								args = { "-w" },
								stdin = true,
							}
						end,
					},
					cpp = {
						function()
							return {
								exe = "clang-format",
								args = { "--assume-filename", vim.fn.fnameescape(vim.api.nvim_buf_get_name(0)) },
								stdin = true,
								cwd = vim.fn.expand("%:p:h"),
							}
						end,
					},
					rust = {
						function()
							return {
								exe = "rustfmt",
								args = { "--emit=stdout" },
								stdin = true,
							}
						end,
					},
					zig = {
						function()
							return {
								exe = "zig",
								args = { "fmt", vim.fn.fnameescape(vim.api.nvim_buf_get_name(0)) },
								stdin = false,
							}
						end,
					},
					nim = {
						function()
							return {
								exe = "nimpretty",
								args = { "--backup:off", vim.fn.fnameescape(vim.api.nvim_buf_get_name(0)) },
								stdin = false,
							}
						end,
					},
					python = {
						function()
							return {
								exe = "black",
								args = { "-" },
								stdin = true,
							}
						end,
					},
					sh = {
						function()
							return {
								exe = "shfmt",
								args = { "-i", "4", "-w", "-s" },
								stdin = true,
							}
						end,
					},
					zsh = {
						function()
							return {
								exe = "shfmt",
								args = { "-i", "4", "-w", "-s" },
								stdin = true,
							}
						end,
					},
					make = {
						function()
							return {
								exe = "gmake",
								args = { "-f", vim.fn.fnameescape(vim.api.nvim_buf_get_name(0)) },
								stdin = false,
							}
						end,
					},
					yaml = {
						function()
							return {
								exe = "prettier",
								args = { "--stdin-filepath", vim.fn.fnameescape(vim.api.nvim_buf_get_name(0)) },
								stdin = true,
							}
						end,
					},
					json = {
						function()
							return {
								exe = "jq",
								args = { "." },
								stdin = true,
							}
						end,
					},
					proto = {
						function()
							return {
								exe = "clang-format",
								args = { "--assume-filename", vim.fn.fnameescape(vim.api.nvim_buf_get_name(0)) },
								stdin = true,
								cwd = vim.fn.expand("%:p:h"),
							}
						end,
					},
				},
			})
		end,
	},
	-- linter
	{
		"mfussenegger/nvim-lint",
		config = function()
			local lint = safe_require("lint")
			lint.linters_by_ft = {
				buf = { "buf" },
				cpp = { "clangtidy" },
				go = { "golangcilint" },
				make = { "checkmake" },
				nim = { "nimlint" },
				proto = { "protoc-gen-lint" },
				python = { "flake8", "pylint" },
				rust = { "clippy" },
				sh = { "shellcheck" },
				yaml = { "yamllint" },
				zig = { "zigfmt" },
			}

			lint.linters.golangcilint = {
				cmd = "golangci-lint",
				args = { "run", "--out-format", "json" },
				stream = "stdout",
				parser = safe_require("lint.parser").from_errorformat("[%trror] %f:%l:%c: %m, [%tarning] %f:%l:%c: %m", {
					source = "golangcilint",
				}),
			}

			vim.api.nvim_create_autocmd("BufWritePost", {
				pattern = "*",
				callback = function()
					safe_require("lint").try_lint()
				end,
			})
		end,
	},
	-- Language specific plugins and configurations
	{
		"rust-lang/rust.vim",
		ft = { "rust" },
		config = function()
			vim.g.rustfmt_autosave = 1
		end,
	},
	{
		"ziglang/zig.vim",
		ft = { "zig" },
	},
	{
		"alaviss/nim.nvim",
		ft = { "nim" },
	},
	{
		"vim-python/python-syntax",
		ft = { "python" },
		config = function()
			vim.g.python_highlight_all = 1
		end,
	},
	-- Debug Adapter Protocol
	{
		"mfussenegger/nvim-dap",
		ft = { "c", "cpp", "rust", "go" },
		config = function()
			local dap = safe_require("dap")
			dap.adapters.lldb = {
				type = "executable",
				command = "/usr/bin/lldb-vscode", -- adjust as needed
				name = "lldb",
			}
			dap.configurations.cpp = {
				{
					name = "Launch",
					type = "lldb",
					request = "launch",
					program = function()
						return fn.input("Path to executable: ", fn.getcwd() .. "/", "file")
					end,
					cwd = "${workspaceFolder}",
					stopOnEntry = false,
					args = {},

					runInTerminal = false,
				},
			}
			dap.configurations.c = dap.configurations.cpp
		end,
	},
}, {
	root = pkg_path,
})

safe_require("onedark").load()

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.diagnostic.on_publish_diagnostics, {
	underline = true,
	virtual_text = {
		spacing = 4,
		prefix = "",
		format = function(diagnostic, virtual_text)
			return string.format("%s %s (%s: %s)", virtual_text, diagnostic.message, diagnostic.source, diagnostic.code)
		end,
	},
	signs = true,
	update_in_insert = false,
})
