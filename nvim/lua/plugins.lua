-----------------------------------------------------------
-- この設定ファイルは以下を実現します：
-- - lazy.nvim によるプラグイン管理（自動ブートストラップ）
-- - lsp-zero.nvim による LSP の設定（ホストに既にインストール済みのサーバーを利用）
--   ※ Nim 用の nimlsp はカスタム設定を追加
-- - nvim-cmp の管理は lsp-zero に任せる（manage_nvim_cmp = true）
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
vim.opt.updatetime = 200 -- LSP/補完の反応速度改善のため200msに短縮
vim.opt.lazyredraw = true
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "preview" }
vim.opt.shortmess:append("c")

-- 3. 安全なモジュール読み込み用関数
local function safe_require(module_name)
	local status, module = pcall(require, module_name)
	if not status then
		vim.notify("Error loading module: " .. module_name, vim.log.levels.ERROR)
		return nil
	end
	return module
end

-----------------------------------------------------------
-- 4. lazy.nvim を用いたプラグイン設定
-----------------------------------------------------------
safe_require("lazy").setup({
	------------------------------------------------------------------
	-- Plugin: blink.nvim (LSP の設定)
	------------------------------------------------------------------
	{
		"saghen/blink.cmp",
		version = "*",
		event = "InsertEnter",
		lazy = true,
		dependencies = {
			{
				"saghen/blink.compat",
				version = "*",
				lazy = true,
				opts = {},
			},
			{ "rafamadriz/friendly-snippets" },
			{ "fang2hou/blink-copilot" },
			{ "neovim/nvim-lspconfig" },
			{
				"L3MON4D3/LuaSnip",
				version = "v2.*",
				build = "make install_jsregexp",
			},
			{ "onsails/lspkind.nvim" },
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
			{
				"zbirenbaum/copilot.lua",
				cmd = "Copilot",
				event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
				config = function()
					safe_require("copilot").setup({
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
								position = "bottom", -- | top | left | right
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
						copilot_node_command = "node", -- Node.js version must be > 16.x
						server_opts_overrides = {
							autostart = true, -- Ensure Copilot autostarts
						},
						on_status_update = function()
							local lualine = safe_require("luasnip")
							if lualine then
								lualine.refresh()
							end
						end,
					})
				end,
			},
		},
		opts = {
			keymap = {
				preset = "enter",
				["<Tab>"] = { "select_next", "fallback" },
				["<S-Tab>"] = { "select_prev", "fallback" },
				["<C-Space>"] = { "show", "fallback" },
				["<C-e>"] = { "hide", "fallback" },
				["<CR>"] = { "confirm", "fallback" }, -- Enter キーで補完候補を確定
			},
			snippets = {
				preset = "default" | "luasnip" | "mini_snippets",
				expand = function(args)
					local luasnip = safe_require("luasnip")
					if luasnip then
						luasnip.lsp_expand(args.body)
					end
				end,
				default = { "lsp", "path", "snippets", "buffer", "copilot", "git" },
				providers = {
					copilot = {
						name = "copilot",
						module = "blink-copilot",
						score_offset = 100,
						async = true,
					},
				},
			},
			completion = {
				keyword = { range = "prefix" },
				documentation = {
					auto_show = true,
					auto_show_delay_ms = 200,
				},
				ghost_text = {
					enabled = false,
				},
			},
			formatting = {
				format = function()
					local lspkind = safe_require("lspkind")
					if lspkind then
						lspkind.cmp_format({
							mode = "symbol_text",
							preset = "codicons",
							maxwidth = 50,
							ellipsis_char = "...",
							menu = {
								copilot = "[COP]",
								nvim_lua = "[LUA]",
								nvim_lsp = "[LSP]",
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
								Interface = "",
								Key = "",
								Keyword = " ",
								Method = " ",
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
								Text = " ",
								TypeParameter = " ",
								Unit = " ",
								Value = " ",
								Variable = "",
							},
						})
					end
				end,
			},
			sources = {
				default = { "lsp", "path", "snippets", "buffer", "copilot", "git" },
			},
			sorting = {
				priority_weight = 2,
			},
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
			experimental = {
				ghost_text = false,
				native_menu = false,
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
		},
		config = function()
			local function get_cmd(env_var, fallback)
				local env = os.getenv(env_var)
				if env and env ~= "" then
					return env .. "/bin/" .. fallback
				else
					return fallback
				end
			end

			local lsputil = safe_require("lspconfig.util")
			local lspconfig = safe_require("lspconfig")
			if lspconfig then
				if lsputil then
					local on_attach = function(client, bufnr)
						local opts = { buffer = bufnr, remap = false }
						vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
						vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
						vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
						vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
						vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
						vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, opts)
						vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
						vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
						vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
						vim.keymap.set("n", "<leader>e", vim.diagnostic.show_line_diagnostics, opts)
						vim.keymap.set("n", "<leader>q", vim.diagnostic.set_loclist, opts)
						vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
						vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
						vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
						vim.keymap.set("n", "<leader>rr", vim.lsp.buf.references, opts)

						vim.cmd("lua vim.lsp.buf.format({ async = true })")

						vim.notify("on_attach executed")
					end
					local capabilities = vim.lsp.protocol.make_client_capabilities()
					local blink = safe_require("blink.cmp")
					if blink then
						capabilities = blink.get_lsp_capabilities(capabilities)
					end
					lspconfig.clangd.setup({
						cmd = { "/usr/bin/clangd", "--background-index" },
						capabilities = capabilities,
						filetypes = { "c", "cpp", "objc", "objcpp" },
						root_dir = lsputil and lsputil.root_pattern("compile_commands.json", "compile_flags.txt", ".git") or nil,
						on_attach = on_attach,
					})
					-- local gocfg = {}
					-- local golsp = safe_require("go.lsp")
					-- if golsp then
					-- 	gocfg = golsp.config()
					-- end
					-- gocfg.on_attach = on_attach
					-- lspconfig.gopls.setup(gocfg)
					lspconfig.rust_analyzer.setup({
						cmd = { get_cmd("CARGO_HOME", "rust-analyzer") },
						capabilities = capabilities,
						filetypes = { "rust" },
						settings = {
							["rust-analyzer"] = {
								cargo = { allFeatures = true },
								checkOnSave = { command = "clippy" },
							},
						},
						root_dir = lsputil and lsputil.root_pattern("Cargo.toml", "rust-project.json", ".git") or nil,
						on_attach = on_attach,
					})
				end
			end
		end,
	},
	------------------------------------------------------------------
	-- Plugin: 言語特有のPlugin
	------------------------------------------------------------------
	{
		"ray-x/go.nvim",
		event = { "CmdlineEnter" },
		ft = { "go", "gomod" },
		config = function()
			local capabilities = vim.lsp.protocol.make_client_capabilities()
			local blink = safe_require("blink.cmp")
			if blink then
				capabilities = blink.get_lsp_capabilities(capabilities)
			end
			local go = safe_require("go")
			if go then
				go.setup({
					gofmt = "gofumpt", -- gofumpt は gofmt の代替
					goimports = "goimports",
					fillstruct = "gopls",
					gofmt_on_save = true,
					goimport_on_save = true,
					lsp_cfg = {
						-- capabilities = safe_require("blink.cmp").get_lsp_capabilities(vim.lsp.protocol.make_client_capabilities()),
						capabilities = capabilities,
					},
					lsp_gofumpt = true, -- gofumpt を使用
					lsp_on_attach = true,
					dap_debug = true,
				})
			end
		end,
		dependencies = {
			"ray-x/guihua.lua",
			"neovim/nvim-lspconfig",
			"nvim-treesitter/nvim-treesitter",
		},
		build = ':lua require("go.install").update_all_sync()',
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
	-- Plugin: SourceGraph Cody の統合 (sg.nvim)
	------------------------------------------------------------------
	-- {
	-- 	"sourcegraph/sg.nvim",
	-- 	event = { "LspAttach" },
	-- 	config = true,
	-- },
	------------------------------------------------------------------
	-- Plugin: nvim-treesitter (シンタックスハイライト・インデント)
	------------------------------------------------------------------
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
					autotag = { enable = true },
					ensure_installed = { "bash", "c", "cpp", "go", "lua", "rust", "zig", "nim", "python" },
					highlight = { enable = true },
					indent = { enable = true },
					sync_install = false,
				})
			end
		end,
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
			local function selectionCount()
				local mode = vim.fn.mode()
				local start_line, end_line, start_pos, end_pos
				-- 選択モードでない場合には無効
				if not (mode:find("[vV\22]") ~= nil) then
					return ""
				end
				start_line = vim.fn.line("v")
				end_line = vim.fn.line(".")
				if mode == "V" then
					-- 行選択モードの場合は、各行全体をカウントする
					start_pos = 1
					end_pos = vim.fn.strlen(vim.fn.getline(end_line)) + 1
				else
					start_pos = vim.fn.col("v")
					end_pos = vim.fn.col(".")
				end
				local chars = 0
				for i = start_line, end_line do
					local line = vim.fn.getline(i)
					local line_len = vim.fn.strlen(line)
					local s_pos = (i == start_line) and start_pos or 1
					local e_pos = (i == end_line) and end_pos or line_len + 1
					chars = chars + vim.fn.strchars(line:sub(s_pos, e_pos - 1))
				end
				local lines = math.abs(end_line - start_line) + 1
				return tostring(lines) .. " lines, " .. tostring(chars) .. " characters"
			end
			local lualine = safe_require("lualine")
			if lualine then
				lualine.setup({
					options = {
						icons_enabled = true,
						theme = "palenight",
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
	-- 以下、効率的な開発を支援する追加プラグイン
	------------------------------------------------------------------

	-- telescope: ファジーファインダー（ファイル検索、ライブグレップ等）
	{
		"nvim-telescope/telescope.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			local telescope = safe_require("telescope")
			if telescope then
				telescope.setup({
					defaults = {
						prompt_prefix = " ",
						selection_caret = " ",
						i = {
							["<C-n>"] = safe_require("telescope.actions").move_selection_next,
							["<C-p>"] = safe_require("telescope.actions").move_selection_previous,
						},
					},
				})
			end
		end,
		cmd = "Telescope",
	},

	-- gitsigns: Git 差分表示
	{
		"lewis6991/gitsigns.nvim",
		event = "BufRead",
		opts = {
			-- 修正: signs を関数で返す形式に変更
			signs = {
				add = { hl = "GitGutterAdd", text = "┃", numhl = "GitGutterAdd" },
				change = { hl = "GitGutterChange", text = "┃", numhl = "GitGutterChange" },
				delete = { hl = "GitGutterDelete", text = "_", numhl = "GitGutterDelete" },
				topdelete = { hl = "GitGutterDelete", text = "‾", numhl = "GitGutterDelete" },
				changedelete = { hl = "GitGutterChange", text = "~", numhl = "GitGutterChange" },
				untracked = { hl = "GitGutterUntracked", text = "┆", numhl = "GitGutterUntracked" },
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
			max_file_length = 40000,
			preview_config = {
				border = "single",
				style = "minimal",
				relative = "cursor",
				row = 0,
				col = 1,
			},
		},
		config = function()
			local gitsigns = safe_require("gitsigns")
			if gitsigns then
				gitsigns.setup()
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

	-- Comment.nvim: Ctrl+C でコメント切替
	{
		"numToStr/Comment.nvim",
		event = "BufReadPost",
		config = true,
		lazy = true,
		opts = {
			ignore = "^$",
		},
		keys = function()
			local capi = safe_require("Comment.api")
			if capi then
				return {
					{
						"<C-c>",
						function()
							capi.toggle.linewise.current()
						end,
						desc = "",
						mode = "n",
						noremap = true,
						silent = true,
					},
					{
						"<C-c>",
						function()
							capi.toggle.linewise(fn.visualmode())
						end,
						desc = "",
						mode = "x",
						noremap = true,
						silent = true,
					},
					{
						"<C-c>",
						function()
							capi.toggle.linewise.current()
						end,
						desc = "",
						mode = "i",
						noremap = true,
						silent = true,
					},
				}
			end
		end,
	},

	-- nvim-autopairs: 自動括弧補完
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		config = function()
			local npairs = safe_require("nvim-autopairs")
			if npairs then
				npairs.setup({})
			end
		end,
	},

	-- persisted.nvim: セッション管理
	{
		"olimorris/persisted.nvim",
		config = function()
			local persisted = safe_require("persisted")
			if persisted then
				persisted.setup({
					use_git_branch = true,
				})
			end
		end,
		cmd = { "SessionSave", "SessionLoad" },
	},
}, {
	root = fn.stdpath("config") .. "/lazy", -- プラグイン配置ディレクトリ
})

-- onedark カラーシェーマのロード
local onedark = safe_require("onedark").load()
-----------------------------------------------------------
-- 5. グローバルキーマッピング
-----------------------------------------------------------
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { silent = true, noremap = true })

-----------------------------------------------------------
-- End of configuration
-----------------------------------------------------------
