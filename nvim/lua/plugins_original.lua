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

-- Ensure installed list
local ensure_installed_list = {
	"bash",
	"beautysh",
	"black",
	"c",
	"clangd",
	"cmake",
	"cpp",
	"cspell",
	"css",
	"cuda",
	"dart",
	"dockerfile",
	"dockerls",
	"eslint_d",
	"gitignore",
	"go",
	"golangci_lint",
	"gomod",
	"gopls",
	"graphql",
	"html",
	"http",
	"java",
	"javascript",
	"json",
	"json5",
	"jsonlint",
	"julia",
	"kotlin",
	"llvm",
	"lua",
	"make",
	"markdown",
	"markdown_inline",
	"markdownlint",
	"meson",
	"nim",
	"nimls",
	"ninja",
	"nix",
	"prettierd",
	"proto",
	"pyright",
	"python",
	"regex",
	"rego",
	"rust",
	"rust_analyzer",
	"shellcheck",
	"sql",
	"sql_formatter",
	"stylua",
	"toml",
	"tsserver",
	"typescript",
	"v",
	"vim",
	"yaml",
	"yamlfmt",
	"yamlls",
	"zig",
	"zls",
}

safe_require("lazy").setup({
	{
		"dstein64/vim-startuptime",
		cmd = "StartupTime",
		init = function()
			vim.g.startuptime_tries = 10
		end,
	},
	{
		"hrsh7th/nvim-cmp",
		event = { "InsertEnter", "CmdlineEnter" },
		opts = function()
			local cmp = safe_require("cmp")
			local capabilities =
				safe_require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
			local on_attach = function(client, bufnr)
				vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
			end
			cmp.setup.cmdline({ "/", "?" }, {
				mapping = cmp.mapping.preset.cmdline(),
				sources = {
					{ name = "buffer", get_bufnrs = vim.api.nvim_list_bufs, keyword_length = 2 },
				},
			})
			cmp.setup.cmdline(":", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = cmp.config.sources({
					{ name = "path" },
				}, {
					{ name = "cmdline", keyword_length = 2 },
				}),
			})
			cmp.setup.filetype("gitcommit", {
				sources = cmp.config.sources({
					{ name = "git" },
				}, {
					{ name = "buffer", get_bufnrs = vim.api.nvim_list_bufs, keyword_length = 2 },
				}),
			})
			cmp.setup.filetype("lua", {
				sources = cmp.config.sources({
					{ name = "copilot_cmp", keyword_length = 2 },
					{ name = "nvim_lsp", keyword_length = 3 },
					{ name = "luasnip" },
					{ name = "cmp_tabnine" },
					{ name = "nvim_lua" },
				}),
			})
			cmp.event:on("confirm_done", safe_require("nvim-autopairs.completion.cmp").on_confirm_done())
			return {
				flags = {
					debounce_text_changes = 150,
				},
				snippet = {
					expand = function(args)
						safe_require("luasnip").lsp_expand(args.body)
					end,
				},
				sources = cmp.config.sources({
					{ name = "copilot_cmp", keyword_length = 2 },
					{ name = "nvim_lsp" },
					{ name = "nvim_lsp", keyword_length = 3 },
					{ name = "luasnip" },
					{ name = "cmp_tabnine" },
					{ name = "nvim_lsp_signature_help" },
					{ name = "buffer", get_bufnrs = vim.api.nvim_list_bufs, keyword_length = 2 },
					{ name = "path" },
					{
						name = "look",
						keyword_length = 2,
						option = {
							convert_case = true,
							loud = true,
							-- dict = '/usr/share/dict/words'
						},
					},
					{ name = "cmdline" },
					{ name = "git" },
				}),
				window = {
					completion = cmp.config.window.bordered({
						border = "single",
						col_offset = -3,
						side_padding = 0,
					}),
					documentation = cmp.config.window.bordered({
						border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
						winhiglight = "NormalFloat:CompeDocumentation,FloatBorder:TelescopeBorder",
					}),
				},
				formatting = {
					format = safe_require("lspkind").cmp_format({
						mode = "symbol_text",
						preset = "codicons",
						-- with_text = false,
						maxwidth = 50,
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
			}
		end,
		dependencies = {
			{ "neovim/nvim-lspconfig", event = "InsertEnter" },
			{ "L3MON4D3/LuaSnip", build = "make install_jsregexp", event = "InsertEnter" },
			{ "hrsh7th/cmp-buffer", event = "InsertEnter" },
			{ "hrsh7th/cmp-calc", event = "InsertEnter" },
			{ "hrsh7th/cmp-cmdline", event = "ModeChanged" },
			{ "hrsh7th/cmp-nvim-lsp", event = "InsertEnter" },
			{ "hrsh7th/cmp-nvim-lsp-document-symbol", event = "InsertEnter" },
			{ "hrsh7th/cmp-nvim-lsp-signature-help", event = "InsertEnter" },
			{ "hrsh7th/cmp-nvim-lua", event = "InsertEnter" },
			{ "hrsh7th/cmp-path", event = "InsertEnter" },
			{ "ray-x/cmp-treesitter", event = "InsertEnter" },
			{ "petertriho/cmp-git", config = true, event = "InsertEnter" },
			{ "octaltree/cmp-look", config = true, event = "InsertEnter" },
			{ "onsails/lspkind.nvim", event = "InsertEnter" },
			{ "rafamadriz/friendly-snippets", event = "InsertEnter" },
			{ "saadparwaiz1/cmp_luasnip", event = "InsertEnter" },
		},
	},
	{
		"L3MON4D3/LuaSnip",
		event = "InsertCharPre",
		config = function()
			safe_require("luasnip").config.set_config({
				history = true,
				updateevents = "TextChanged,TextChangedI",
			})
			safe_require("luasnip.loaders.from_vscode").lazy_load()
		end,
	},
	{
		"tzachar/cmp-tabnine",
		build = "./install.sh",
		dependencies = "hrsh7th/nvim-cmp",
		config = true,
		opts = {
			max_lines = 1000,
			max_num_results = 20,
			sort = true,
			run_on_every_keystroke = true,
			snippet_placeholder = "..",
			ignored_file_types = {
				-- default is not to ignore
				-- uncomment to ignore in lua:
				-- lua = true
			},
			show_prediction_strength = false,
		},
		event = { "InsertEnter", "VeryLazy" },
	},
	{
		"zbirenbaum/copilot.lua",
		enabled = true,
		event = "InsertEnter",
		lazy = false,
		opts = {
			panel = {
				enabled = true,
				auto_refresh = false,
				layout = {
					position = "bottom",
					ratio = 0.4,
				},
			},
			suggestion = {
				enabled = false,
				auto_trigger = true,
				debounce = 75,
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
			copilot_node_command = "node",
			server_opts_overrides = {},
		},
		config = true,
	},
	{
		"zbirenbaum/copilot-cmp",
		lazy = false,
		event = "InsertEnter",
		config = true,
	},
	{
		"numToStr/Comment.nvim",
		config = true,
		lazy = true,
		opts = {
			ignore = "^$",
		},
	},
	{
		"neovim/nvim-lspconfig",
		event = { "InsertEnter", "CmdlineEnter", "BufReadPost" },
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"nvimtools/none-ls.nvim",
			"nvimtools/none-ls-extras.nvim",
		},
		lazy = true,
		config = function()
			local lspconfig = safe_require("lspconfig")
			local null_ls = safe_require("null-ls")

			local servers = { "gopls", "rust_analyzer", "tsserver", "pyright", "clangd", "zls", "nimls", "bashls", "yamlls" }

			local on_attach = function(client, bufnr)
				vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
			end

			for _, lsp in ipairs(servers) do
				lspconfig[lsp].setup({
					on_attach = on_attach,
					flags = {
						debounce_text_changes = 150,
					},
				})
			end

			null_ls.setup({
				sources = {
					null_ls.builtins.formatting.stylua,
					null_ls.builtins.completion.spell,
					safe_require("none-ls.diagnostics.eslint"),
					safe_require("none-ls.diagnostics.cpplint"),
					safe_require("none-ls.formatting.jq"),
					safe_require("none-ls.code_actions.eslint"),
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
		config = function(_, opts)
			local ntsi = safe_require("nvim-treesitter.install")
			ntsi.compilers = { "clang" }
			ntsi.update({ with_sync = true })
			safe_require("nvim-treesitter.configs").setup(opts)
		end,
		opts = {
			auto_install = true,
			sync_install = false,
			highlight = {
				enable = true,
			},
			indent = {
				enable = true,
			},
			ensure_installed = ensure_installed_list,
			autotag = {
				enable = true,
			},
		},
	},
	{
		"norcalli/nvim-colorizer.lua",
		config = true,
	},
	{
		"williamboman/mason-lspconfig.nvim",
		event = "InsertEnter",
		opts = {
			ensure_installed = ensure_installed_list,
			automatic_installation = true,
		},
	},
	{
		"glepnir/lspsaga.nvim",
		lazy = true,
		branch = "main",
		opts = { border_style = "rounded" },
		dependencies = "neovim/nvim-lspconfig",
		config = function()
			safe_require("lspsaga").init_lsp_saga({
				server_filetype_map = {
					typescript = "typescript",
				},
			})
		end,
	},
	{
		"nvimtools/none-ls.nvim",
		branch = "main",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"jay-babu/mason-null-ls.nvim",
				opts = {
					ensure_installed = ensure_installed_list,
					automatic_setup = true,
					automatic_installation = true,
				},
				config = true,
			},
		},
		config = true,
	},
	{
		"nvimtools/none-ls-extras.nvim",
		config = true,
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
		"nvim-lualine/lualine.nvim",
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
		"lewis6991/gitsigns.nvim",
		config = true,
		opts = {
			signs = {
				add = { hl = "GitSignsAdd", text = "│", numhl = "GitSignsAddNr", linehl = "GitSignsAddLn" },
				change = {
					hl = "GitSignsChange",
					text = "│",
					numhl = "GitSignsChangeNr",
					linehl = "GitSignsChangeLn",
				},
				delete = { hl = "GitSignsDelete", text = "_", numhl = "GitSignsDeleteNr", linehl = "GitSignsDeleteLn" },
				topdelete = {
					hl = "GitSignsDelete",
					text = "‾",
					numhl = "GitSignsDeleteNr",
					linehl = "GitSignsDeleteLn",
				},
				changedelete = {
					hl = "GitSignsChange",
					text = "~",
					numhl = "GitSignsChangeNr",
					linehl = "GitSignsChangeLn",
				},
			},
			signcolumn = true,
			numhl = false,
			linehl = false,
			word_diff = false,
			watch_gitdir = {
				interval = 1000,
				follow_files = true,
			},
			attach_to_untracked = true,
			current_line_blame = false,
			current_line_blame_opts = {
				virt_text = true,
				virt_text_pos = "eol",
				delay = 1000,
				ignore_whitespace = false,
			},
			current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
			sign_priority = 6,
			update_debounce = 100,
			status_formatter = nil,
			max_file_length = 40000,
			preview_config = {
				border = "single",
				style = "minimal",
				relative = "cursor",
				row = 0,
				col = 1,
			},
			yadm = {
				enable = false,
			},
		},
	},
	{
		"SmiteshP/nvim-navic",
		dependencies = "neovim/nvim-lspconfig",
		config = true,
	},
	{
		"windwp/nvim-autopairs",
		opts = {
			disable_filetype = { "TelescopePrompt", "vim" },
		},
		config = true,
	},
	{
		"windwp/nvim-ts-autotag",
		config = true,
	},
	{
		"mfussenegger/nvim-lint",
		event = "BufReadPost",
		config = function()
			local lint = safe_require("lint")
			lint.linters_by_ft = {
				go = { "golangcilint" },
				python = { "flake8" },
				lua = { "luacheck" },
				rust = { "clippy" },
				yaml = { "yamllint" },
				sh = { "shellcheck" },
			}
			vim.api.nvim_create_autocmd("BufWritePost", {
				callback = function()
					safe_require("lint").try_lint()
				end,
			})
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
	{
		"akinsho/flutter-tools.nvim",
		ft = { "dart" },
		config = function()
			safe_require("flutter-tools").setup({})
		end,
	},
	{
		"mfussenegger/nvim-dap",
		ft = { "c", "cpp", "rust", "go" },
		config = function()
			local dap = safe_require("dap")
			dap.adapters.lldb = {
				type = "executable",
				command = "/usr/bin/lldb-vscode",
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
	{
		"fatih/vim-go",
		ft = { "go" },
		config = function()
			vim.g.go_fmt_command = "goimports"
		end,
	},
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
	{
		"tbastos/vim-lua",
		ft = { "lua" },
	},
	{
		"towolf/vim-helm",
		ft = { "yaml" },
	},
	{
		"juliosueiras/vim-terraform-completion",
		ft = { "tf" },
	},
	{
		"mattn/vim-sonictemplate",
		cmd = "Template",
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

-- Keymaps
local keymaps = {
	-- LSP
	{
		"n",
		"gD",
		"<cmd>lua vim.lsp.buf.declaration()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"gd",
		"<cmd>lua vim.lsp.buf.definition()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"K",
		"<cmd>lua vim.lsp.buf.hover()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"gi",
		"<cmd>lua vim.lsp.buf.implementation()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<C-k>",
		"<cmd>lua vim.lsp.buf.signature_help()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>wa",
		"<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>wr",
		"<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>wl",
		"<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>D",
		"<cmd>lua vim.lsp.buf.type_definition()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>rn",
		"<cmd>lua vim.lsp.buf.rename()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"gr",
		"<cmd>lua vim.lsp.buf.references()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>ca",
		"<cmd>lua vim.lsp.buf.code_action()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>e",
		"<cmd>lua vim.diagnostic.open_float()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"[d",
		"<cmd>lua vim.diagnostic.goto_prev()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"]d",
		"<cmd>lua vim.diagnostic.goto_next()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>q",
		"<cmd>lua vim.diagnostic.setloclist()<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>f",
		"<cmd>lua vim.lsp.buf.formatting()<CR>",
		{ noremap = true, silent = true },
	},
	-- Telescope
	{
		"n",
		"<C-p>",
		":Telescope find_files<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<C-f>",
		":Telescope live_grep<CR>",
		{ noremap = true, silent = true },
	},
	-- Bufferline
	{
		"n",
		"<Tab>",
		"<Cmd>BufferLineCycleNext<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<S-Tab>",
		"<Cmd>BufferLineCyclePrev<CR>",
		{ noremap = true, silent = true },
	},
	-- Gitsigns
	{
		"n",
		"]c",
		function()
			if vim.wo.diff then
				return "]c"
			end
			vim.schedule(function()
				safe_require("gitsigns").next_hunk()
			end)
			return "<Ignore>"
		end,
		{ expr = true, noremap = true, silent = true },
	},
	{
		"n",
		"[c",
		function()
			if vim.wo.diff then
				return "[c"
			end
			vim.schedule(function()
				safe_require("gitsigns").prev_hunk()
			end)
			return "<Ignore>"
		end,
		{ expr = true, noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hs",
		"<Cmd>Gitsigns stage_hunk<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hr",
		"<Cmd>Gitsigns reset_hunk<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hS",
		"<Cmd>Gitsigns stage_buffer<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hR",
		"<Cmd>Gitsigns reset_buffer<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hu",
		"<Cmd>Gitsigns undo_stage_hunk<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hp",
		"<Cmd>Gitsigns preview_hunk<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hb",
		function()
			safe_require("gitsigns").blame_line({ full = true })
		end,
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hd",
		"<Cmd>Gitsigns diffthis<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>hD",
		function()
			safe_require("gitsigns").diffthis("~")
		end,
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>tb",
		"<Cmd>Gitsigns toggle_current_line_blame<CR>",
		{ noremap = true, silent = true },
	},
	{
		"n",
		"<leader>td",
		"<Cmd>Gitsigns toggle_deleted<CR>",
		{ noremap = true, silent = true },
	},
	{
		{ "o", "x" },
		"ih",
		"<Cmd>Gitsigns select_hunk<CR>",
		{ noremap = true, silent = true },
	},
	-- Comment
	{
		"n",
		"<C-c>",
		function()
			safe_require("Comment.api").toggle.linewise.current()
		end,
		{ noremap = true, silent = true },
	},
	{
		"x",
		"<C-c>",
		function()
			safe_require("Comment.api").toggle.linewise(vim.fn.visualmode())
		end,
		{ noremap = true, silent = true },
	},
	{
		"i",
		"<C-c>",
		function()
			safe_require("Comment.api").toggle.linewise.current()
		end,
		{ noremap = true, silent = true },
	},
	-- cmp
	{ "i", "<C-b>", "cmp.mapping.scroll_docs(-4)", { noremap = true, silent = true } },
	{ "i", "<C-f>", "cmp.mapping.scroll_docs(4)", { noremap = true, silent = true } },
	{ "i", "<C-Space>", "cmp.mapping.complete()", { noremap = true, silent = true } },
	{ "i", "<C-y>", "cmp.mapping.confirm { select = true }", { noremap = true, silent = true } },
	{ "i", "<C-e>", "cmp.mapping.abort()", { noremap = true, silent = true } },
	{ "i", "<CR>", "cmp.mapping.confirm({ select = true })", { noremap = true, silent = true } },
	{
		"i",
		"<Tab>",
		function(fallback)
			if cmp.visible() then
				cmp.select_next_item()
			elseif luasnip.expand_or_jumpable() then
				luasnip.expand_or_jump()
			else
				fallback()
			end
		end,
		{ noremap = true, silent = true },
	},
	{
		"i",
		"<S-Tab>",
		function(fallback)
			if cmp.visible() then
				cmp.select_prev_item()
			elseif luasnip.jumpable(-1) then
				luasnip.jump(-1)
			else
				fallback()
			end
		end,
		{ noremap = true, silent = true },
	},
}

for _, map in ipairs(keymaps) do
	vim.api.nvim_set_keymap(unpack(map))
end
