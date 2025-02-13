--
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
vim.opt.updatetime = 300
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
require("lazy").setup({

	------------------------------------------------------------------
	-- Plugin: Avante.nvim
	------------------------------------------------------------------
	{
		"yetone/avante.nvim",
		event = "VeryLazy",
		lazy = false,
		version = false,
		opts = {
			provider = "openai",
			openai = {
				endpoint = "https://api.openai.com/v1",
				model = "gpt-o1-mini",
				timeout = 30000,
				temperature = 0,
				max_tokens = 4096,
			},
			vendors = {
				groq = {
					__inherited_from = "openai",
					api_key_name = "GROQ_API_KEY",
					endpoint = "https://api.groq.com/openai/v1/",
					model = "deepseek-r1-distill-llama-70b",
					--model = "llama-3.3-70b-specdec",
					--model = "llama-3.3-70b-versatile",
				},
			},
			behaviour = {
				auto_apply_diff_after_generation = true,
			},
		},
		build = "make",
		dependencies = {
			"MunifTanjim/nui.nvim",
			"nvim-lua/plenary.nvim",
			"stevearc/dressing.nvim",
			--- The below dependencies are optional,
			"echasnovski/mini.pick", -- for file_selector provider mini.pick
			"nvim-telescope/telescope.nvim", -- for file_selector provider telescope
			"hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
			"ibhagwan/fzf-lua", -- for file_selector provider fzf
			"nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
			"zbirenbaum/copilot.lua", -- for providers='copilot'
			{
				-- support for image pasting
				"HakonHarnes/img-clip.nvim",
				event = "VeryLazy",
				opts = {
					-- recommended settings
					default = {
						embed_image_as_base64 = false,
						prompt_for_file_name = false,
						drag_and_drop = {
							insert_mode = true,
						},
						use_absolute_path = false,
					},
				},
			},
			{
				"MeanderingProgrammer/render-markdown.nvim",
				opts = {
					file_types = { "markdown", "Avante" },
				},
				ft = { "markdown", "Avante" },
			},
		},
	},

	------------------------------------------------------------------
	-- Plugin: lsp-zero.nvim (LSP の設定)
	------------------------------------------------------------------
	{
		"VonHeikemen/lsp-zero.nvim",
		branch = "v4.x",
		lazy = false,
		dependencies = {
			{ "neovim/nvim-lspconfig" },
			{ "hrsh7th/nvim-cmp" },
			{ "hrsh7th/cmp-nvim-lsp" },
			{ "hrsh7th/cmp-buffer" },
			{ "hrsh7th/cmp-path" },
			{ "hrsh7th/cmp-cmdline" },
			{ "saadparwaiz1/cmp_luasnip" },
			{ "hrsh7th/cmp-nvim-lua" },
			{ "L3MON4D3/LuaSnip" },
			{ "saadparwaiz1/cmp_luasnip" },
			{ "onsails/lspkind.nvim" },
		},
		config = function()
			-- on_attach や補完の設定が自動で適用される
			local lsp = safe_require("lsp-zero")
			if not lsp then
				return
			end

			local lsputil = safe_require("lspconfig.util")

			local lspconfig = require("lspconfig")
			-- LSPのキーマッピング設定
			lsp.on_attach(function(client, bufnr)
				local opts = { buffer = bufnr, remap = false }

				vim.keymap.set("n", "gd", function()
					vim.lsp.buf.definition()
				end, opts)
				vim.keymap.set("n", "K", function()
					vim.lsp.buf.hover()
				end, opts)
				vim.keymap.set("n", "<leader>vws", function()
					vim.lsp.buf.workspace_symbol()
				end, opts)
				vim.keymap.set("n", "<leader>vd", function()
					vim.diagnostic.open_float()
				end, opts)
				vim.keymap.set("n", "[d", function()
					vim.diagnostic.goto_next()
				end, opts)
				vim.keymap.set("n", "]d", function()
					vim.diagnostic.goto_prev()
				end, opts)
				vim.keymap.set("n", "<leader>ca", function()
					vim.lsp.buf.code_action()
				end, opts)
				vim.keymap.set("n", "<leader>rr", function()
					vim.lsp.buf.references()
				end, opts)
				vim.keymap.set("n", "<leader>rn", function()
					vim.lsp.buf.rename()
				end, opts)
				vim.keymap.set("i", "<C-h>", function()
					vim.lsp.buf.signature_help()
				end, opts)
				lsp.buffer_autoformat()
			end)
			-- 環境変数の存在チェックを実施してコマンドを設定
			local function get_cmd(env_var, fallback)
				local env = os.getenv(env_var)
				if env and env ~= "" then
					return env .. "/bin/" .. fallback
				else
					return fallback
				end
			end

			-- 各言語サーバーの設定
			lspconfig.clangd.setup({
				cmd = { "/usr/bin/clangd", "--background-index" },
				filetypes = { "c", "cpp", "objc", "objcpp" },
				root_dir = lsputil and lsputil.root_pattern("compile_commands.json", "compile_flags.txt", ".git") or nil,
			})
			lspconfig.gopls.setup({
				cmd = { get_cmd("GOPATH", "gopls") },
				filetypes = { "go", "gomod" },
				root_dir = lsputil and lsputil.root_pattern("go.work", "go.mod", "go.sum", ".git") or nil,
				settings = {
					gopls = {
						analyses = {
							unusedparams = true,
							shadow = true,
						},
						staticcheck = true,
						gofumpt = true,
						usePlaceholders = true,
						completeUnimported = true,
						semanticTokens = true,
						codelenses = {
							gc_details = false,
							generate = true,
							regenerate_cgo = true,
							run_govulncheck = true,
							test = true,
							tidy = true,
							upgrade_dependency = true,
							vendor = true,
						},
					},
				},
			})
			lspconfig.rust_analyzer.setup({
				cmd = { get_cmd("CARGO_HOME", "rust-analyzer") },
				filetypes = { "rust" },
				settings = {
					["rust-analyzer"] = {
						cargo = { allFeatures = true },
						checkOnSave = { command = "clippy" },
					},
				},
				root_dir = lsputil and lsputil.root_pattern("Cargo.toml", "rust-project.json", ".git") or nil,
			})

			-- 補完の設定
			local cmp = require("cmp")
			local cmp_select = { behavior = cmp.SelectBehavior.Select }
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

			lsp.setup()
		end,
	},
	------------------------------------------------------------------
	-- Plugin: 言語特有のPlugin
	------------------------------------------------------------------
	{
		"ray-x/go.nvim",
		ft = { "go" },
		config = function()
			safe_require("go").setup({
				gofmt = "gofumpt", -- gofumpt は gofmt の代替
				goimpors = "goimpors", -- gopls による import
				fillstruct = "gopls",
				gofmt_on_save = true,
				goimport_on_save = true,
				lsp_cfg = true,
				lsp_gofumpt = true, -- gofumptを使用
				lsp_on_attach = true,
				dap_debug = true,
			})
		end,
		dependencies = {
			"neovim/nvim-lspconfig",
			"nvim-treesitter/nvim-treesitter",
		},
	},
	------------------------------------------------------------------
	-- Plugin: GitHub Copilot の統合 (copilot.lua)
	------------------------------------------------------------------
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		event = "InsertEnter",
		config = function()
			local copilot = safe_require("copilot")
			if copilot then
				copilot.setup({
					panel = { enabled = true },
					suggestion = { enabled = true },
				})
			end
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
					on_status_update = function()
						safe_require("lualine").refresh()
					end,
				})
			end,
		},
	},

	------------------------------------------------------------------
	-- Plugin: EditorConfig (エディタ設定の統一)
	------------------------------------------------------------------
	{
		"editorconfig/editorconfig-vim",
		lazy = false,
	},

	------------------------------------------------------------------
	-- Plugin: Code Formatter
	------------------------------------------------------------------
	------------------------------------------------------------------
	-- Plugin: nvim-treesitter (シンタックスハイライト・インデント)
	------------------------------------------------------------------
	{
		"nvim-treesitter/nvim-treesitter",
		run = ":TSUpdate",
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
								sources = {
									-- 'nvim_diagnostic',
									"nvim_lsp",
								},

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
						lualine_y = {
							"encoding",
							"fileformat",
							"filetype",
						},
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
		config = function()
			local gitsigns = safe_require("gitsigns")
			if gitsigns then
				gitsigns.setup()
			end
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

safe_require("onedark").load()
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
