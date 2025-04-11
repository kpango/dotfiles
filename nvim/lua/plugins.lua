-----------------------------------------------------------
-- この設定ファイルは以下を実現します：
-- - lazy.nvim によるプラグイン管理（自動ブートストラップ）
--   blink.cmpを用いたGo, Rust, C++, Zig, Nim, V の補完設定
-- - none-ls (nvimtools/none-ls.nvim) によるフォーマッター／リンターの設定
-- - GitHub Copilot (copilot.lua) の統合
-- - EditorConfig の連携
-- - nvim-treesitter によるシンタックスハイライト・インデント
-- - lualine によるステータスライン
-- - 効率的な開発を支援する補助プラグイン：
--   which-key, Telescope, gitsigns, Comment.nvim (Ctrl+C によるコメント切替),
--   indent-blankline (v3仕様), nvim-autopairs, persisted.nvim
-----------------------------------------------------------
-- 1. lazy.nvim の自動ブートストラップ
local fn = vim.fn
local install_path = fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(install_path) then
	fn.system({
		"git",
		"clone",
		"--depth",
		"1",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		install_path,
	})
end
vim.opt.rtp:prepend(install_path)

-- 2. グローバルオプションの設定
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.updatetime = 150
vim.opt.lazyredraw = true
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "preview" }
vim.opt.shortmess:append("c")

-- リーダーキーの設定（プラグイン設定前に行う必要がある）
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- 3. 安全なモジュール読み込み用関数
local function safe_require(module_name)
	local status, module = pcall(require, module_name)
	if not status then
		-- エラーメッセージをより静かに表示（デバッグ用通知を削除）
		vim.defer_fn(function()
			vim.api.nvim_echo({ { "Failed to load module: " .. module_name, "ErrorMsg" } }, false, {})
		end, 100)
		return nil
	end
	return module
end

-- LSP共通のon_attach関数（すべてのLSPサーバーで一貫して使用）
local function on_attach(client, bufnr)
	local opts = { buffer = bufnr, remap = false }

	-- キーマッピングの設定
	vim.keymap.set("n", "<C-h>", vim.lsp.buf.signature_help, opts) -- Insertモードではblink.cmpが<C-k>を使用
	vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
	vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
	vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, opts)
	vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
	vim.keymap.set("n", "<leader>rr", vim.lsp.buf.references, opts)
	vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
	vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
	vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
	vim.keymap.set("n", "<leader>wl", function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
	end, opts)
	vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
	vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
	vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
	vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
	vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
	vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
	vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
	vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)

	-- 保存時の自動フォーマットを設定（非同期実行）
	if client.supports_method("textDocument/formatting") then
		vim.api.nvim_create_autocmd("BufWritePre", {
			buffer = bufnr,
			callback = function()
				vim.lsp.buf.format({ async = false, bufnr = bufnr })
			end,
		})
		vim.keymap.set("n", "<leader>fm", function()
			vim.lsp.buf.format({ async = true })
		end, { buffer = bufnr, desc = "Format Document" })
	end
	-- デバッグ通知を削除（本番環境では不要）
	-- vim.notify("on_attach executed")
end

-----------------------------------------------------------
-- 4. lazy.nvim を用いたプラグイン設定
-----------------------------------------------------------
local lazy = safe_require("lazy")
if lazy then
	lazy.setup({
		------------------------------------------------------------------
		-- Plugin: blink.nvim (LSP の設定)
		------------------------------------------------------------------
		{
			"saghen/blink.cmp",
			version = "*",
			event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
			build = "cargo +nightly build --force --no-default-features --release",
			lazy = true,
			dependencies = {
				{
					"saghen/blink.compat",
					version = "*",
					lazy = true,
					opts = {},
				},
				{ "rafamadriz/friendly-snippets" },
				{ "neovim/nvim-lspconfig" },
				{
					"L3MON4D3/LuaSnip",
					version = "v2.*",
					build = "make install_jsregexp",
				},
				{ "onsails/lspkind.nvim" },
				-- 不要なコメントアウトを削除（依存関係を明確化）
				-- { "hrsh7th/cmp-buffer" },
				-- { "hrsh7th/cmp-calc" },
				-- { "hrsh7th/cmp-cmdline" },
				-- { "hrsh7th/cmp-nvim-lsp" },
				-- { "hrsh7th/cmp-nvim-lua" },
				-- { "hrsh7th/cmp-path" },
				-- { "hrsh7th/nvim-cmp" },
				-- { "saadparwaiz1/cmp_luasnip" },
				-- {
				-- 	"petertriho/cmp-git",
				-- 	config = true,
				-- 	event = "InsertEnter",
				-- 	lazy = true,
				-- 	dependencies = { "nvim-lua/plenary.nvim" },
				-- },
				-- { "octaltree/cmp-look", event = "InsertEnter" },
			},
			opts = {
				optional = true,
				keymap = {
					preset = "super-tab",
					["<Tab>"] = { "select_next", "fallback" },
					["<S-Tab>"] = { "select_prev", "fallback" },
					["<C-Space>"] = { "show", "fallback" },
					["<C-e>"] = { "hide", "fallback" },
					["<CR>"] = { "confirm", "fallback" }, -- Enter キーで補完候補を確定
				},
				snippets = {
					preset = "luasnip",
					expand = function(args)
						local luasnip = safe_require("luasnip")
						if luasnip then
							luasnip.lsp_expand(args.body)
						end
					end,
				},
				completion = {
					keyword = { range = "prefix" },
					documentation = {
						auto_show = true,
						auto_show_delay_ms = 100, -- 200msから100msに短縮して応答性向上
					},
					ghost_text = {
						enabled = true, -- Copilotとの連携のため有効化
					},
				},
				formatting = {
					format = function(entry, item)
						local lspkind = safe_require("lspkind")
						if lspkind then
							return lspkind.cmp_format({
								mode = "symbol_text",
								preset = "codicons",
								maxwidth = 50,
								ellipsis_char = "...",
								menu = {
									lsp = "[LSP]",
									nvim_lsp = "[LSP]",
									buffer = "[Buf]",
									path = "[Path]",
									snippets = "[SNIP]",
									look = "[LK]",
									luasnip = "[LSN]",
									nvim_lua = "[LUA]",
									copilot = "[COP]",
								},
								symbol_map = {
									Array = "",
									Boolean = "",
									Class = " ",
									Color = " ",
									Constant = " ",
									Constructor = "",
									Copilot = "",
									Enum = " ",
									EnumMember = " ",
									Event = " ",
									Field = " ",
									File = " ",
									Folder = " ",
									Function = "",
									Interface = " ",
									Key = "",
									Keyword = " ",
									Method = "",
									Module = "",
									Namespace = "",
									Null = "",
									Number = "",
									Object = "",
									Operator = " ",
									Package = "",
									Property = " ",
									Reference = " ",
									Snippet = "",
									String = "",
									Struct = " ",
									Text = "",
									TypeParameter = " ",
									Unit = " ",
									Value = " ",
									Variable = "",
								},
							})(entry, item)
						end
						return vim_item
					end,
				},
				sources = {
					default = { "lsp", "path", "snippets", "buffer", "copilot", "omni", "git" },
					providers = {
						copilot = {
							name = "copilot",
							module = "blink-copilot",
							score_offset = 100,
							async = true,
						},
					},
				},
				sorting = {
					priority_weight = 2,
					comparators = function()
						local compare = safe_require("cmp.config.compare")
						return {
							compare.offset,
							compare.exact,
							compare.score,
							compare.recently_used,
							compare.locality,
							compare.kind,
							compare.sort_text,
							compare.length,
							compare.order,
						}
					end,
				},
				signature = { enabled = true },
				window = {
					completion = {
						bordered = true,
						border = "single",
						col_offset = -3,
						side_padding = 0,
					},
					documentation = {
						bordered = true,
						winhighlight = "NormalFloat:CompeDocumentation,FloatBorder:TelescopeBorder",
					},
				},
				fuzzy = { implementation = "prefer_rust_with_warning" },
				experimental = {
					ghost_text = true, -- Copilotとの連携のため有効化
					native_menu = false,
				},
			},
			opts_extend = { "sources.default" },
			config = function(_, opts)
				local blink = safe_require("blink.cmp")
				if not blink then
					return
				end

				local lspconfig = safe_require("lspconfig")
				if not lspconfig then
					return
				end

				local lsputil = safe_require("lspconfig.util")
				if not lsputil then
					return
				end
				-- LSPサーバー共通の設定を準備
				local capabilities = blink.get_lsp_capabilities(vim.lsp.protocol.make_client_capabilities())
				capabilities.general.positionEncodings = { "utf-16" }

				-- C/C++の設定
				lspconfig.clangd.setup({
					cmd = { "/usr/bin/clangd", "--background-index" },
					capabilities = capabilities,
					filetypes = { "c", "cpp", "objc", "objcpp" },
					root_dir = lsputil and lsputil.root_pattern("compile_commands.json", "compile_flags.txt", ".git") or nil,
					on_attach = on_attach,
				})

				-- Goの設定
				local go = safe_require("go")
				if go then
					local gocfg = go and go.lsp and go.lsp.config() or {}
					gocfg.capabilities = capabilities
					gocfg.on_attach = on_attach
					lspconfig.gopls.setup(gocfg)
				end
				-- lspconfig.gopls.setup({
				-- 	capabilities = capabilities,
				-- 	cmd = { "gopls", "-remote=auto" },
				-- 	settings = {
				-- 		gopls = {
				-- 			usePlaceholders = true,
				-- 			completeUnimported = true,
				-- 			analyses = { unusedparams = true, nilness = true, unusedwrite = true },
				-- 		},
				-- 	},
				-- 	on_attach = on_attach,
				-- })

				-- Rustの設定
				lspconfig.rust_analyzer.setup({
					cmd = { (os.getenv("CARGO_HOME") or os.getenv("HOME") .. "/.cargo") .. "/bin/rust-analyzer" },
					capabilities = capabilities,
					filetypes = { "rust" },
					settings = {
						["rust-analyzer"] = {
							cargo = { allFeatures = true },
							checkOnSave = { command = "clippy" },
							-- procMacro設定を追加してマクロ展開を改善
							procMacro = { enable = true },
							-- 型ヒントの設定を追加
							inlayHints = {
								maxLength = 25,
								typeHints = { enable = true },
								parameterHints = { enable = true },
							},
						},
					},
					root_dir = lsputil and lsputil.root_pattern("Cargo.toml", "rust-project.json", ".git") or nil,
					on_attach = on_attach,
				})

				if vim.fn.executable("zls") == 1 then
					-- Zigの設定を追加
					lspconfig.zls.setup({
						capabilities = capabilities,
						on_attach = on_attach,
					})
				end

				if vim.fn.executable("pyright") == 1 then
					-- Pythonの設定を追加
					lspconfig.pyright.setup({
						capabilities = capabilities,
						on_attach = on_attach,
						settings = {
							python = {
								analysis = {
									autoSearchPaths = true,
									diagnosticMode = "workspace",
									useLibraryCodeForTypes = true,
								},
							},
						},
					})
				end

				if vim.fn.executable("nimls") == 1 then
					-- Nimの設定を追加
					lspconfig.nimls.setup({
						capabilities = capabilities,
						on_attach = on_attach,
					})
				end
			end,
		},

		{
			"zbirenbaum/copilot.lua",
			cmd = "Copilot",
			build = ":Copilot auth",
			event = "BufReadPost",
			dependencies = { "fang2hou/blink-copilot" },
			opts = {
				panel = {
					enabled = true,
					auto_refresh = true,
					keymap = {
						jump_prev = "[[",
						jump_next = "]]",
						accept = "<CR>",
						refresh = "gr",
						open = "<M-CR>",
					},
					layout = {
						position = "bottom",
						ratio = 0.4,
					},
				},
				suggestion = {
					enabled = true,
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
				auth_provider_url = { "https://api.github.com" },
				server_opts_overrides = {
					autostart = true,
				},
				on_status_update = function()
					local lualine = safe_require("lualine")
					if lualine then
						lualine.refresh()
					end
				end,
			},
			config = true,
		},
		------------------------------------------------------------------
		-- Plugin: 言語特有のPlugin
		------------------------------------------------------------------
		{
			"ray-x/go.nvim",
			event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
			ft = { "go", "gomod" },
			opts = {
				gofmt = "gofumpt",
				goimports = "goimports",
				fillstruct = "gopls",
				gofmt_on_save = true,
				goimport_on_save = true,
				lsp_cfg = true, -- goplsのセットアップをプラグイン側で行わない
				lsp_on_attach = false,
				dap_debug = true,
			},
			config = function(_, opts)
				local go = safe_require("go")
				if go then
					go.setup(opts)
				end
			end,
			dependencies = {
				"ray-x/guihua.lua",
				"neovim/nvim-lspconfig",
				"nvim-treesitter/nvim-treesitter",
			},
			-- build = ':lua require("go.install").update_all_sync()',
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
		------------------------------------------------------------------
		-- Plugin: nvim-treesitter (シンタックスハイライト・インデント)
		------------------------------------------------------------------
		{
			"nvim-treesitter/nvim-treesitter",
			build = ":TSUpdate",
			event = "BufReadPost",
			dependencies = {
				"nvim-treesitter/nvim-treesitter-textobjects",
				{
					"navarasu/onedark.nvim",
					opts = { style = "darker" },
					config = function(_, opts)
						local onedark = safe_require("onedark")
						if onedark then
							onedark.setup(opts)
							onedark.load()
						end
					end,
				},
			},
			config = function()
				local ts_configs = safe_require("nvim-treesitter.configs")
				if ts_configs then
					ts_configs.setup({
						auto_install = true,
						autotag = { enable = true },
						ensure_installed = { "bash", "c", "cpp", "go", "lua", "rust", "zig", "nim", "python" },
						highlight = { enable = true },
						indent = { enable = true },
						sync_install = false,
						-- インクリメンタル選択機能を追加
						incremental_selection = {
							enable = true,
							keymaps = {
								init_selection = "gnn",
								node_incremental = "grn",
								scope_incremental = "grc",
								node_decremental = "grm",
							},
						},
					})
				end
			end,
		},
		{
			"mvllow/modes.nvim",
			event = "BufReadPre",
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
		------------------------------------------------------------------
		-- Plugin: bufferline (Tabステータス)
		------------------------------------------------------------------
		{
			"akinsho/bufferline.nvim",
			version = "*",
			dependencies = "nvim-tree/nvim-web-devicons",
			config = true,
			opts = {
				options = {
					mode = "buffers",
					separator_style = "slant",
					always_show_bufferline = true,
					show_buffer_close_icons = true,
					show_close_icon = true,
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
						bold = true,
					},
					fill = {
						bg = "#073642",
					},
				},
			},
		},
		------------------------------------------------------------------
		-- Plugin: lualine (ステータスライン)
		------------------------------------------------------------------
		{
			"nvim-lualine/lualine.nvim",
			event = "VeryLazy",
			dependencies = {
				"nvim-tree/nvim-web-devicons",
				"takeshid/avante-status.nvim",
			},
			config = function()
				local selectionCount = function()
					local mode = vim.fn.mode()
					if not mode:match("[vV\22]") then
						return ""
					end -- ビジュアルモードでなければ空
					local start_line = vim.fn.line("v")
					local end_line = vim.fn.line(".")
					local start_col = (mode == "V") and 1 or vim.fn.col("v")
					local end_col = (mode == "V") and (vim.fn.col("$") - 1) or vim.fn.col(".")
					-- 行数と文字数を計算
					local lines = math.abs(end_line - start_line) + 1
					local chars = 0
					for l = start_line, end_line do
						local line_text = vim.fn.getline(l)
						local from = (l == start_line) and start_col or 1
						local to = (l == end_line) and end_col or #line_text
						chars = chars + vim.fn.strchars(line_text:sub(from, to))
					end
					return lines .. " lines, " .. chars .. " chars"
				end
				local lualine = safe_require("lualine")
				if lualine then
					lualine.setup({
						options = {
							icons_enabled = true,
							theme = "onedark",
							component_separators = { left = "", right = "" },
							section_separators = { left = "", right = "" },
							disabled_filetypes = {
								statusline = {},
								winbar = {},
							},
							ignore_focus = {},
							always_divide_middle = true,
							globalstatus = true,
							refresh = {
								statusline = 1000,
								tabline = 1000,
								winbar = 1000,
							},
						},
						sections = {
							lualine_a = { "mode" },
							lualine_b = {
								"branch",
								"diff",
								{
									"diagnostics",
									sources = { "nvim_lsp" },
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
										modified = " [+]",
										readonly = " [RO]",
										unnamed = "Untitled",
									},
								},
							},
							lualine_x = {
								{ "searchcount" },
								{ selectionCount },
								{
									"diagnostics",
									sources = { "nvim_lsp" },
									sections = { "error", "warn", "info", "hint" },
									diagnostics_color = {
										error = "DiagnosticError",
										warn = "DiagnosticWarn",
										info = "DiagnosticInfo",
										hint = "DiagnosticHint",
									},
									symbols = {
										error = " ",
										warn = " ",
										info = " ",
										hint = " ",
									},
									colored = true,
									update_in_insert = false,
									always_visible = false,
								},
							},
							lualine_y = { "encoding", "fileformat", "filetype" },
							lualine_z = { "progress", "location" },
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
						tabline = {
							lualine_a = {
								{
									"buffers",
									mode = 4,
									icons_enabled = true,
									show_filename_only = true,
									hide_filename_extensions = false,
								},
							},
							lualine_b = {},
							lualine_c = {},
							lualine_x = {},
							lualine_y = {},
							lualine_z = { "tabs" },
						},
						extensions = { "fugitive", "fzf", "nvim-tree" },
					})
				end
			end,
		},
		------------------------------------------------------------------
		-- Plugin: Telescope (ファジーファインダー)
		------------------------------------------------------------------
		{
			"nvim-telescope/telescope.nvim",
			dependencies = {
				"nvim-lua/plenary.nvim",
				{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
			},
			cmd = "Telescope",
			keys = {
				{ "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
				{ "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Grep" },
				{ "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
				{ "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
			},
			config = function()
				local telescope = safe_require("telescope")
				if telescope then
					telescope.setup({
						defaults = {
							prompt_prefix = "🔍 ",
							selection_caret = " ",
							path_display = { "smart" },
							file_ignore_patterns = { ".git/", "node_modules" },
							mappings = {
								i = {
									["<C-n>"] = safe_require("telescope.actions").move_selection_next,
									["<C-p>"] = safe_require("telescope.actions").move_selection_previous,
								},
							},
						},
						extensions = {
							fzf = {
								fuzzy = true,
								override_generic_sorter = true,
								override_file_sorter = true,
								case_mode = "smart_case",
							},
						},
					})
					telescope.load_extension("fzf")
				end
			end,
			cmd = "Telescope",
		},
		------------------------------------------------------------------
		-- Plugin: gitsigns (Gitの変更表示)
		------------------------------------------------------------------
		{
			"lewis6991/gitsigns.nvim",
			event = { "BufReadPre", "BufNewFile" },
			opts = {
				-- signs = {
				-- 	add = { hl = "GitGutterAdd", text = "┃", numhl = "GitGutterAdd" },
				-- 	change = { hl = "GitGutterChange", text = "┃", numhl = "GitGutterChange" },
				-- 	delete = { hl = "GitGutterDelete", text = "_", numhl = "GitGutterDelete" },
				-- 	topdelete = { hl = "GitGutterDelete", text = "‾", numhl = "GitGutterDelete" },
				-- 	changedelete = { hl = "GitGutterChange", text = "~", numhl = "GitGutterChange" },
				-- 	untracked = { hl = "GitGutterUntracked", text = "┆", numhl = "GitGutterUntracked" },
				-- },
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
				max_file_length = 40000,
				preview_config = {
					border = "single",
					style = "minimal",
					relative = "cursor",
					row = 0,
					col = 1,
				},
			},
			config = function(_, opts)
				local gitsigns = safe_require("gitsigns")
				if gitsigns then
					gitsigns.setup(opts)
				end
			end,
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
		------------------------------------------------------------------
		-- Plugin: Comment.nvim (コメント切替)
		------------------------------------------------------------------
		{
			"numToStr/Comment.nvim",
			event = "BufReadPost",
			opts = {
				ignore = "^$",
				padding = true,
				sticky = true,
				toggler = {
					line = "gcc",
					block = "gbc",
				},
				opleader = {
					line = "gc",
					block = "gb",
				},
				extra = {
					above = "gcO",
					below = "gco",
					eol = "gcA",
				},
				mappings = {
					basic = true,
					extra = true,
					extended = false,
				},
				pre_hook = nil,
				post_hook = nil,
			},
			keys = function()
				local capi = safe_require("Comment.api")
				if capi then
					return {
						{
							"<C-c>",
							capi.toggle.linewise.current,
							desc = "Toggle comment",
							mode = "n",
							noremap = true,
							silent = true,
						},
						{
							"<C-c>",
							function()
								local fn = vim.fn
								capi.toggle.linewise(fn.visualmode())
							end,
							desc = "Toggle comment",
							mode = "x",
							noremap = true,
							silent = true,
						},
						{
							"<C-c>",
							capi.toggle.linewise.current,
							desc = "Toggle comment",
							mode = "i",
							noremap = true,
							silent = true,
						},
					}
				end
			end,
			config = function(_, opts)
				local comment = safe_require("Comment")
				if comment then
					comment.setup(opts)
				end
			end,
		},
		------------------------------------------------------------------
		-- Plugin: nvim-autopairs (自動ペア補完)
		------------------------------------------------------------------
		{
			"windwp/nvim-autopairs",
			event = "InsertEnter",
			config = function()
				local npairs = safe_require("nvim-autopairs")
				if npairs then
					npairs.setup({
						check_ts = true,
						ts_config = {
							lua = { "string", "source" },
							javascript = { "string", "template_string" },
							java = false,
						},
						disable_filetype = { "TelescopePrompt", "spectre_panel" },
						fast_wrap = {
							map = "<M-e>",
							chars = { "{", "[", "(", '"', "'" },
							pattern = string.gsub([[ [%'%"%)%>%]%)%}%,] ]], "%s+", ""),
							offset = 0,
							end_key = "$",
							keys = "qwertyuiopzxcvbnmasdfghjkl",
							check_comma = true,
							highlight = "PmenuSel",
							highlight_grey = "LineNr",
						},
					})

					-- cmpとの連携設定
					local blink = safe_require("blink.cmp")
					if blink then
						local cmp_autopairs = safe_require("nvim-autopairs.completion.blink")
						if cmp_autopairs then
							blink.event:on("confirm_done", cmp_autopairs.on_confirm_done())
						end
					end
				end
			end,
		},
		-- persisted.nvim: セッション管理
		{
			"olimorris/persisted.nvim",
			cmd = { "SessionSave", "SessionLoad" },
			opts = {
				use_git_branch = true,
				autosave = true, -- 自動保存を有効化
				autoload = false, -- 自動読み込みは無効化
				follow_cwd = true, -- カレントディレクトリに従う
				allowed_dirs = nil, -- 全てのディレクトリを許可
				ignored_dirs = nil, -- 無視するディレクトリなし
			},
			config = function(_, opts)
				local persisted = safe_require("persisted")
				if persisted then
					persisted.setup(opts)
				end
			end,
			cmd = { "SessionSave", "SessionLoad", "SessionDelete" },
			keys = {
				{ "<leader>ss", "<cmd>SessionSave<cr>", desc = "Save Session" },
				{ "<leader>sl", "<cmd>SessionLoad<cr>", desc = "Load Session" },
				{ "<leader>sd", "<cmd>SessionDelete<cr>", desc = "Delete Session" },
			},
		},
		------------------------------------------------------------------
		-- Plugin: none-ls.nvim (フォーマッターとリンター)
		------------------------------------------------------------------
		-- {
		-- 	"nvimtools/none-ls.nvim",
		-- 	event = { "BufReadPre", "BufNewFile" },
		-- 	dependencies = { "nvim-lua/plenary.nvim" },
		-- 	config = function()
		-- 		local null_ls = safe_require("null-ls")
		-- 		if null_ls then
		-- 			null_ls.setup({
		-- 				sources = {
		-- 					-- フォーマッター
		-- 					null_ls.builtins.formatting.prettier,
		-- 					null_ls.builtins.formatting.stylua,
		-- 					null_ls.builtins.formatting.gofumpt,
		-- 					null_ls.builtins.formatting.shfmt,
		-- 					null_ls.builtins.formatting.rustfmt,
		-- 					null_ls.builtins.formatting.clang_format,

		-- 					-- リンター
		-- 					null_ls.builtins.diagnostics.eslint,
		-- 					null_ls.builtins.diagnostics.shellcheck,
		-- 					null_ls.builtins.diagnostics.golangci_lint,
		-- 					null_ls.builtins.diagnostics.luacheck,
		-- 					null_ls.builtins.diagnostics.cpplint,

		-- 					-- コード補完
		-- 					null_ls.builtins.completion.spell,
		-- 				},
		-- 				on_attach = on_attach,
		-- 			})
		-- 		end
		-- 	end,
		-- },
	}, {
		root = fn.stdpath("config") .. "/lazy", -- プラグイン配置ディレクトリ
	})
end

-- onedark カラーシェーマのロード
local onedark = safe_require("onedark")
if onedark then
	onedark.load()
end

-----------------------------------------------------------
-- 5. グローバルキーマッピング
-----------------------------------------------------------
-- Telescopeのキーマッピングはプラグイン定義内に移動済み

-- ウィンドウ操作のキーマッピング
vim.keymap.set("n", "<C-h>", "<C-w>h", { silent = true, noremap = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { silent = true, noremap = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { silent = true, noremap = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { silent = true, noremap = true })

-- バッファ操作のキーマッピング
vim.keymap.set("n", "<leader>bn", ":bnext<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>bp", ":bprevious<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>bd", ":bdelete<CR>", { silent = true, noremap = true })

-- 検索ハイライトをクリア
vim.keymap.set("n", "<Esc><Esc>", ":nohlsearch<CR>", { silent = true, noremap = true })

-- 行の移動（ビジュアルモードでも選択を維持）
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { silent = true, noremap = true })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { silent = true, noremap = true })

-- 自動保存の設定
vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave" }, {
	pattern = "*",
	command = "silent! wall",
	nested = true,
})

-----------------------------------------------------------
-- End of configuration
-----------------------------------------------------------
