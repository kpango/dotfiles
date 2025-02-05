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

-- Add lazy.nvim to runtime path
vim.opt.rtp:prepend(lazypath)
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "preview" }
vim.opt.shortmess:append("c")

-- Function to safely require a module
local function safe_require(module_name)
	local status, module = pcall(require, module_name)
	if not status then
		vim.api.nvim_err_writeln("Error loading module: " .. module_name .. " is not installed. Install path: " .. pkg_path)
		return nil
	end
	return module
end

-- List of languages, LSP servers and tools
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

-- Setup lazy.nvim with plugins
safe_require("lazy").setup({

	----------------------------------------------------------------
	-- nvim-cmp および LSP 関連の設定
	{
		"hrsh7th/nvim-cmp",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = {
			{
				"neovim/nvim-lspconfig",
				event = "BufReadPre",
				dependencies = {
					{
						"williamboman/mason.nvim",
						config = function()
							local mason = safe_require("mason")
							if mason then
								mason.setup({
									ui = {
										icons = {
											package_installed = "✓",
											package_pending = "➜",
											package_uninstalled = "✗",
										},
									},
								})
							end
						end,
					},
					{
						"williamboman/mason-lspconfig.nvim",
						config = function()
							local mason_lspconfig = safe_require("mason-lspconfig")
							if mason_lspconfig then
								mason_lspconfig.setup({ ensure_installed = lsps })
							end
						end,
					},
					{
						"ray-x/go.nvim",
						ft = { "go" },
						config = true,
						opts = {
							gofmt = "gofumpt",
							goimports = "strictgoimports",
							lsp_cfg = true,
						},
					},
					{ "hrsh7th/cmp-nvim-lsp", event = { "InsertEnter", "BufReadPre" } },
					{
						"ray-x/lsp_signature.nvim",
						event = { "InsertEnter", "BufReadPre" },
						config = function()
							local lsp_signature = safe_require("lsp_signature")
							if lsp_signature then
								lsp_signature.setup({
									bind = true, -- 必須: バッファに自動的にハンドラーをバインドする
									extra_trigger_chars = { "(", "," }, -- トリガー文字の指定
									fix_pos = true, -- ポジションの固定
									floating_window = true, -- フローティングウィンドウを有効にする
									handler_opts = { border = "none" }, -- ウィンドウの枠線設定
									hi_parameter = "PmenuSel", -- 現在のパラメータをハイライトするためのハイライトグループ
									hint_enable = true, -- ヒント表示を有効にする
									hint_prefix = " ", -- ヒントのプレフィックス
									max_height = 12, -- ウィンドウの最大高さ
									max_width = 120, -- ウィンドウの最大幅
									timer_interval = 200, -- 更新間隔（ミリ秒）
									toggle_key = "<C-x>", -- signatureHelp のトグルキー
									zindex = 99, -- ウィンドウの z-index
								})
							end
						end,
					},
				},
				config = function()
					local lspconfig = safe_require("lspconfig")
					if not lspconfig then
						return
					end

					local golsp = safe_require("go.lsp")
					local servers = {
						gopls = golsp and golsp.config() or {},
						rust_analyzer = {
							settings = {
								["rust-analyzer"] = {
									cargo = { allFeatures = true },
									checkOnSave = { command = "clippy" },
								},
							},
						},
						clangd = {},
						dockerls = {},
						lua_ls = {
							settings = {
								Lua = {
									runtime = { version = "LuaJIT", path = vim.split(package.path, ";") },
									diagnostics = { globals = { "vim" } },
									workspace = { library = vim.api.nvim_get_runtime_file("", true), checkThirdParty = false },
									telemetry = { enable = false },
								},
							},
						},
						nimls = {},
						pyright = {
							settings = {
								python = { analysis = { typeCheckingMode = "strict" } },
							},
						},
						zls = {},
					}

					local default_config = {
						on_attach = function(client, bufnr)
							vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
							if client.server_capabilities.document_highlight then
								local group = vim.api.nvim_create_augroup("lsp_document_highlight", { clear = false })
								vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
									group = group,
									buffer = bufnr,
									callback = vim.lsp.buf.document_highlight,
								})
								vim.api.nvim_create_autocmd("CursorMoved", {
									group = group,
									buffer = bufnr,
									callback = vim.lsp.buf.clear_references,
								})
							end
						end,
						flags = { debounce_text_changes = 150 },
						capabilities = (safe_require("cmp_nvim_lsp") or {}).default_capabilities
								and safe_require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
							or vim.lsp.protocol.make_client_capabilities(),
					}

					for _, server_name in ipairs(lsps) do
						local server_config = servers[server_name] or {}
						lspconfig[server_name].setup(vim.tbl_deep_extend("force", default_config, server_config))
					end
				end,
			},
			{
				"L3MON4D3/LuaSnip",
				build = "make install_jsregexp",
				event = "InsertEnter",
				config = function()
					local luasnip = safe_require("luasnip")
					if luasnip then
						luasnip.config.set_config({
							history = true,
							updateevents = "TextChanged,TextChangedI",
						})
						local vscode_loader = safe_require("luasnip.loaders.from_vscode")
						if vscode_loader then
							vscode_loader.lazy_load()
						end
					end
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
			{
				"zbirenbaum/copilot-cmp",
				after = { "copilot.lua", "nvim-cmp" },
				event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
				fix_pairs = true,
				config = true,
				dependencies = {
					{
						"zbirenbaum/copilot.lua",
						event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
						config = function()
							local copilot = safe_require("copilot")
							if copilot then
								copilot.setup({
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
										layout = { position = "bottom", ratio = 0.4 },
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
									copilot_node_command = "node",
									server_opts_overrides = { autostart = true },
									on_status_update = function()
										local lualine = safe_require("lualine")
										if lualine then
											lualine.refresh()
										end
									end,
								})
							end
						end,
					},
				},
			},
		},
		config = function()
			local cmp = safe_require("cmp")
			local luasnip = safe_require("luasnip")
			local lspkind = safe_require("lspkind")
			if not cmp or not luasnip or not lspkind then
				return
			end

			local has_words_before = function()
				if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then
					return false
				end
				local line, col = unpack(vim.api.nvim_win_get_cursor(0))
				local text = vim.api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]
				return col ~= 0 and text and not text:match("^%s*$")
			end

			local check_backspace = function()
				local col = vim.fn.col(".") - 1
				return col == 0 or vim.fn.getline("."):sub(col, col):match("%s")
			end

			cmp.setup({
				flags = { debounce_text_changes = 150 },
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
						else
							local copilot_suggestion = safe_require("copilot.suggestion")
							if copilot_suggestion and copilot_suggestion.is_visible() then
								copilot_suggestion.accept()
							elseif luasnip.expandable() then
								luasnip.expand()
							elseif luasnip.expand_or_jumpable() then
								luasnip.expand_or_jump()
							elseif check_backspace() then
								fallback()
							else
								fallback()
							end
						end
					end, { "i", "s" }),
					["<S-Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() and has_words_before() then
							cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
						elseif luasnip.jumpable(-1) then
							luasnip.jump(-1)
						else
							fallback()
						end
					end, { "i", "s" }),
				},
				sources = cmp.config.sources({
					{ name = "copilot", group_index = 2 },
					{ name = "copilot_cmp", group_index = 2 },
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
						safe_require("copilot_cmp.comparators") and safe_require("copilot_cmp.comparators").prioritize or nil,
						cmp.config.compare.offset,
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
					-- 修正："winhiglight" → "winhighlight"
					documentation = cmp.config.window.bordered({
						winhighlight = "NormalFloat:CompeDocumentation,FloatBorder:TelescopeBorder",
					}),
				},
				formatting = {
					format = lspkind.cmp_format({
						mode = "symbol_text",
						preset = "codicons",
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
							Field = "",
							File = " ",
							Folder = "",
							Function = " ",
							Interface = "",
							Key = "",
							Keyword = "",
							Method = " ",
							Module = "",
							Namespace = "",
							Null = "",
							Number = "",
							Object = "",
							Operator = " ",
							Package = "",
							Property = "",
							Reference = " ",
							Snippet = "",
							String = "",
							Struct = " ",
							Text = "",
							TypeParameter = "",
							Unit = " ",
							Value = "",
							Variable = "",
						},
					}),
				},
				keys = {
					{ "gD", vim.lsp.buf.declaration, mode = "n", noremap = true, silent = true },
					{ "gd", vim.lsp.buf.definition, mode = "n", noremap = true, silent = true },
					{ "gr", vim.lsp.buf.references, mode = "n", noremap = true, silent = true },
					{ "gi", vim.lsp.buf.implementation, mode = "n", noremap = true, silent = true },
					{ "K", vim.lsp.buf.hover, mode = "n", noremap = true, silent = true },
					{ "<C-k>", vim.lsp.buf.signature_help, mode = "n", noremap = true, silent = true },
					{ "<space>wa", vim.lsp.buf.add_workspace_folder, mode = "n", noremap = true, silent = true },
					{ "<space>wr", vim.lsp.buf.remove_workspace_folder, mode = "n", noremap = true, silent = true },
					{
						"<space>wl",
						function()
							print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
						end,
						mode = "n",
						noremap = true,
						silent = true,
					},
					{ "<space>D", vim.lsp.buf.type_definition, mode = "n", noremap = true, silent = true },
					{ "<space>rn", vim.lsp.buf.rename, mode = "n", noremap = true, silent = true },
					{ "<space>ca", vim.lsp.buf.code_action, mode = "n", noremap = true, silent = true },
					{
						"<space>f",
						function()
							vim.lsp.buf.format({ async = true })
						end,
						mode = "n",
						noremap = true,
						silent = true,
					},
					{
						"<space>e",
						vim.diagnostic.open_float or vim.diagnostic.show_line_diagnostics,
						mode = "n",
						noremap = true,
						silent = true,
					},
					{
						"<space>q",
						vim.diagnostic.setloclist or vim.diagnostic.set_loclist,
						mode = "n",
						noremap = true,
						silent = true,
					},
					{ "[d", vim.diagnostic.goto_prev, mode = "n", noremap = true, silent = true },
					{ "]d", vim.diagnostic.goto_next, mode = "n", noremap = true, silent = true },
				},
				experimental = {
					ghost_text = false,
					native_menu = false,
				},
			})
		end,
	},

	----------------------------------------------------------------
	-- nvim-treesitter の設定（build キーに変更）
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate", -- run → build に変更
		event = "BufReadPost",
		dependencies = {
			"nvim-treesitter/nvim-treesitter-textobjects",
			{ "navarasu/onedark.nvim", config = true, opts = { style = "darker" } },
		},
		config = function()
			local ts_configs = safe_require("nvim-treesitter.configs")
			if ts_configs then
				ts_configs.setup({
					auto_install = true,
					sync_install = false,
					ensure_installed = languages,
					highlight = { enable = true },
					indent = { enable = true },
					autotag = { enable = true },
				})
			end
		end,
	},

	----------------------------------------------------------------
	-- copilot-cmp 再設定（依存プラグインのテーブル指定に修正）
	{
		"zbirenbaum/copilot-cmp",
		after = { "copilot.lua", "nvim-cmp" },
		event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
		fix_pairs = true,
		config = true,
		dependencies = {
			{
				"zbirenbaum/copilot.lua",
				event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
				config = function()
					local copilot = safe_require("copilot")
					if copilot then
						copilot.setup({
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
								layout = { position = "bottom", ratio = 0.4 },
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
							copilot_node_command = "node",
							server_opts_overrides = { autostart = true },
							on_status_update = function()
								local lualine = safe_require("lualine")
								if lualine then
									lualine.refresh()
								end
							end,
						})
					end
				end,
			},
		},
	},

	----------------------------------------------------------------
	-- CopilotChat の設定
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		branch = "main",
		dependencies = {
			{ "zbirenbaum/copilot.lua" },
			{ "nvim-lua/plenary.nvim" },
		},
		build = "make tiktoken",
		config = true,
		opts = {
			debug = true,
			show_help = "yes",
			window = { layout = "float", relative = "editor" },
			prompts = {
				Explain = {
					prompt = "/COPILOT_EXPLAIN 選択されたコードの説明を段落をつけて書いてください。",
					mapping = "<leader>ce",
					description = "コードの説明をお願いする",
				},
				Review = {
					prompt = "/COPILOT_REVIEW 選択されたコードをレビューしてください。",
					mapping = "<leader>cr",
					description = "コードのレビューをお願いする",
				},
				Fix = {
					prompt = "/COPILOT_FIX このコードには問題があります。バグを修正したコードに書き直してください。",
					mapping = "<leader>cf",
					description = "コードの修正をお願いする",
				},
				Optimize = {
					prompt = "/COPILOT_REFACTOR 選択されたコードを最適化してパフォーマンスと可読性を向上させてください。",
					mapping = "<leader>co",
					description = "コードの最適化をお願いする",
				},
				Docs = {
					prompt = "/COPILOT_DOCS 選択されたコードに対してドキュメンテーションコメントを追加してください。",
					mapping = "<leader>cd",
					description = "コードのドキュメント作成をお願いする",
				},
				Tests = {
					prompt = "/COPILOT_TESTS 選択されたコードの詳細な単体テスト関数を書いてください。",
					mapping = "<leader>ct",
					description = "テストコード作成をお願いする",
				},
				FixDiagnostic = {
					prompt = "ファイル内の次のような診断上の問題を解決してください:",
					mapping = "<leader>cd",
					description = "コードの修正をお願いする",
					selection = function(source)
						return safe_require("CopilotChat.select").diagnostics(source, true)
					end,
				},
				Commit = {
					prompt = "実装差分に対するコミットメッセージを日本語で記述してください。",
					mapping = "<leader>cco",
					description = "コミットメッセージの作成をお願いする",
					selection = function(source)
						return require("CopilotChat.select").gitdiff(source, true)
					end,
				},
				CommitStaged = {
					prompt = "ステージ済みの変更に対するコミットメッセージを日本語で記述してください。",
					mapping = "<leader>cs",
					description = "ステージ済みのコミットメッセージの作成をお願いする",
					selection = function(source)
						return require("CopilotChat.select").gitdiff(source, true)
					end,
				},
			},
		},
	},

	----------------------------------------------------------------
	-- Comment プラグイン
	{
		"numToStr/Comment.nvim",
		event = "BufReadPost",
		config = true,
		lazy = true,
		opts = { ignore = "^$" },
		keys = {
			{
				"<C-c>",
				function()
					local comment_api = safe_require("Comment.api")
					if comment_api then
						comment_api.toggle.linewise.current()
					end
				end,
				mode = "n",
				noremap = true,
				silent = true,
			},
			{
				"<C-c>",
				function()
					local comment_api = safe_require("Comment.api")
					if comment_api then
						comment_api.toggle.linewise(fn.visualmode())
					end
				end,
				mode = "x",
				noremap = true,
				silent = true,
			},
			{
				"<C-c>",
				function()
					local comment_api = safe_require("Comment.api")
					if comment_api then
						comment_api.toggle.linewise.current()
					end
				end,
				mode = "i",
				noremap = true,
				silent = true,
			},
		},
	},

	----------------------------------------------------------------
	-- lualine と nvim-navic の設定（navic コンポーネントを直接テーブルで指定）
	{
		"nvim-lualine/lualine.nvim",
		event = "VimEnter",
		dependencies = { "nvim-tree/nvim-web-devicons", "SmiteshP/nvim-navic" },
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
					{ "diagnostics", sources = { "nvim_lsp", "coc" }, update_in_insert = true, always_visible = true },
				},
				lualine_c = {
					{
						"filename",
						path = 1,
						file_status = true,
						shorting_target = 40,
						symbols = { modified = "[+]", readonly = "[RO]", unnamed = "Untitled" },
					},
					{
						function()
							local navic = safe_require("nvim-navic")
							return navic and navic.get_location() or ""
						end,
						cond = function()
							local navic = safe_require("nvim-navic")
							return navic and navic.is_available()
						end,
					},
				},
				lualine_x = {
					{
						"diagnostics",
						sources = { "nvim_diagnostic" },
						symbols = { error = " ", warn = " ", info = " ", hint = " " },
					},
					"encoding",
					"filetype",
				},
				lualine_y = {
					{ "diagnostics", source = { "nvim-lsp" } },
					"progress",
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
						symbols = { modified = " [+]", readonly = " [RO]", unnamed = "Untitled" },
					},
				},
				lualine_x = { "filetype" },
				lualine_y = { "%p%%", "location" },
				lualine_z = {},
			},
			tabline = {},
			extensions = { "fugitive", "fzf", "nvim-tree" },
		},
		config = true,
	},

	----------------------------------------------------------------
	-- その他各種プラグイン（bufferline, autopairs, gitsigns, telescope, formatter, lint, 各言語固有の設定, DAP など）
	{
		"mvllow/modes.nvim",
		config = true,
		opts = {
			colors = { copy = "#FFEE55", delete = "#DC669B", insert = "#55AAEE", visual = "#DD5522" },
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
				complex = { [".*git/config"] = "gitconfig" },
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
				shebang = { dash = "sh" },
			},
		},
	},
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = { "nvim-tree/nvim-web-devicons" },
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
				separator = { fg = "#073642", bg = "#002b36" },
				separator_selected = { fg = "#073642" },
				background = { fg = "#657b83", bg = "#002b36" },
				buffer_selected = { fg = "#fdf6e3" },
				fill = { bg = "#073642" },
			},
		},
	},
	{
		"windwp/nvim-autopairs",
		opts = { disable_filetype = { "TelescopePrompt", "vim" } },
		config = true,
	},
	{
		"lewis6991/gitsigns.nvim",
		event = "BufReadPost",
		config = true,
		opts = {
			signs = function()
				return {
					add = { text = "┃" },
					change = { text = "┃" },
					delete = { text = "_" },
					topdelete = { text = "‾" },
					changedelete = { text = "~" },
					untracked = { text = "┆" },
				}
			end,
			signcolumn = true, -- signcolumn の表示設定（必要に応じて）
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
					mode = "n",
					expr = true,
				},
				{
					"<leader>hs",
					"<Cmd>Gitsigns stage_hunk<CR>",
					mode = { "n", "v" },
					silent = true,
					noremap = true,
				},
				{
					"<leader>hr",
					"<Cmd>Gitsigns reset_hunk<CR>",
					mode = { "n", "v" },
					silent = true,
					noremap = true,
				},
				{ "<leader>hS", gs.stage_buffer, mode = "n", silent = true, noremap = true },
				{ "<leader>hR", gs.reset_buffer, mode = "n", silent = true, noremap = true },
				{ "<leader>hu", gs.undo_stage_hunk, mode = "n", silent = true, noremap = true },
				{ "<leader>hp", gs.preview_hunk, mode = "n", silent = true, noremap = true },
				{
					"<leader>hb",
					function()
						gs.blame_line({ full = true })
					end,
					mode = "n",
					silent = true,
					noremap = true,
				},
				{ "<leader>hd", gs.diffthis, mode = "n", silent = true, noremap = true },
				{
					"<leader>hD",
					function()
						gs.diffthis("~")
					end,
					mode = "n",
					silent = true,
					noremap = true,
				},
				{ "<leader>tb", gs.toggle_current_line_blame, mode = "n", silent = true, noremap = true },
				{ "<leader>td", gs.toggle_deleted, mode = "n", silent = true, noremap = true },
				{ "ih", "<Cmd>Gitsigns select_hunk<CR>", mode = { "o", "x" }, silent = true, noremap = true },
			}
		end,
	},
	{
		"nvim-telescope/telescope.nvim",
		cmd = "Telescope",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			local telescope = safe_require("telescope")
			if not telescope then
				return
			end
			local actions = require("telescope.actions")
			local fb_actions = require("telescope").extensions.file_browser
					and require("telescope").extensions.file_browser.actions
				or {}
			telescope.setup({
				defaults = {
					mappings = {
						n = { ["q"] = actions.close },
						i = {
							["<C-n>"] = actions.move_selection_next,
							["<C-p>"] = actions.move_selection_previous,
						},
					},
				},
				extensions = {
					file_browser = {
						theme = "dropdown",
						hijack_netrw = true,
						mappings = {
							["i"] = {
								["<C-w>"] = function()
									vim.cmd("normal vbd")
								end,
							},
							["n"] = {
								["N"] = fb_actions.create or function() end,
								["h"] = fb_actions.goto_parent_dir or function() end,
								["/"] = function()
									vim.cmd("startinsert")
								end,
							},
						},
					},
				},
			})
			telescope.load_extension("file_browser")
		end,
	},
	{
		"mhartington/formatter.nvim",
		event = "BufWritePost",
		config = function()
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = vim.api.nvim_create_augroup("FormatAutogroup", { clear = true }),
				pattern = "*",
				command = "FormatWrite",
			})

			local formatter = safe_require("formatter")
			if formatter then
				formatter.setup({
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
			end
		end,
	},
	{
		"mfussenegger/nvim-lint",
		config = function()
			local lint = safe_require("lint")
			if not lint then
				return
			end

			lint.linters_by_ft = {
				buf = { "buf" },
				cpp = { "clangtidy" },
				go = { "golangcilint" },
				make = { "checkmake" },
				nim = { "nimlint" },
				proto = { "protoc-gen-lint" },
				python = { "flake8", "pylint" },
				sh = { "shellcheck" },
				yaml = { "yamllint" },
				zig = { "zigfmt" },
			}

			lint.linters.golangcilint = {
				cmd = "golangci-lint",
				args = { "run", "--out-format", "json" },
				stream = "stdout",
				parser = safe_require("lint.parser")
						and safe_require("lint.parser").from_errorformat("[%trror] %f:%l:%c: %m, [%tarning] %f:%l:%c: %m", {
							source = "golangcilint",
						})
					or nil,
			}

			vim.api.nvim_create_autocmd("BufWritePost", {
				pattern = "*",
				callback = function()
					lint.try_lint()
				end,
			})
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
		"mfussenegger/nvim-dap",
		ft = { "c", "cpp", "rust", "go" },
		config = function()
			local dap = safe_require("dap")
			if not dap then
				return
			end
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
}, { root = pkg_path })

-- Load onedark colorscheme
local onedark = safe_require("onedark")
if onedark then
	onedark.load()
end
