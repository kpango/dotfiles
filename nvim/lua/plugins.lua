-----------------------------------------------------------
-- Neovim Full Configuration (init.lua)
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
	-- ※ lazy を無効にして確実にロード
	------------------------------------------------------------------
	{
		"yetone/avante.nvim",
		event = "VeryLazy",
		lazy = false,
		version = false, -- Set this to "*" to always pull the latest release version, or set it to false to update to the latest code changes.
		opts = {
			-- add any opts here
			-- for example
			provider = "openai",
			openai = {
				endpoint = "https://api.openai.com/v1",
				model = "gpt-4o", -- your desired model (or use gpt-4o, etc.)
				timeout = 30000, -- timeout in milliseconds
				temperature = 0, -- adjust if needed
				max_tokens = 4096,
			},
		},
		-- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
		build = "make",
		-- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
		dependencies = {
			"stevearc/dressing.nvim",
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			--- The below dependencies are optional,
			"echasnovski/mini.pick", -- for file_selector provider mini.pick
			"nvim-telescope/telescope.nvim", -- for file_selector provider telescope
			"hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
			"ibhagwan/fzf-lua", -- for file_selector provider fzf
			"nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
			"zbirenbaum/copilot.lua", -- for providers='copilot'
			{
				-- Make sure to set this up properly if you have lazy=true
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
	-- ※ ホストに既にインストール済みの LSP サーバー（clangd, gopls, rust_analyzer, zls, pyright）
	--     およびカスタム設定の nimlsp を利用
	------------------------------------------------------------------
	{
		"VonHeikemen/lsp-zero.nvim",
		branch = "v4.x",
		lazy = false,
		dependencies = {
			{ "neovim/nvim-lspconfig" },
			{ "hrsh7th/nvim-cmp" },
			{ "hrsh7th/cmp-nvim-lsp" },
			{ "hrsh7th/cmp-buffer" }, -- Optional
			{ "hrsh7th/cmp-path" }, -- Optional
			{ "hrsh7th/cmp-cmdline" },
			{ "saadparwaiz1/cmp_luasnip" }, -- Optional
			{ "hrsh7th/cmp-nvim-lua" }, -- Optional
			-- Snippets
			{ "L3MON4D3/LuaSnip" }, -- Required
			{ "saadparwaiz1/cmp_luasnip" },
		},
		config = function()
			local lsp = safe_require("lsp-zero")
			if not lsp then
				return
			end
			local lsputil = safe_require("lspconfig.util")
			if lsputil then
				-- 各言語サーバーごとに、環境変数でバイナリのパスを指定する設定例
				lsp.configure("clangd", {
					cmd = { "/usr/bin/clangd", "--background-index" },
					filetypes = { "c", "cpp", "objc", "objcpp" },
					root_dir = lsputil.root_pattern("compile_commands.json", "compile_flags.txt", ".git"),
				})

				lsp.configure("gopls", {
					cmd = { os.getenv("GOPATH") .. "/bin/gopls" or "gopls" },
					filetypes = { "go", "gomod" },
					root_dir = lsputil.root_pattern("go.work", "go.mod", ".git"),
				})

				lsp.configure("rust_analyzer", {
					cmd = { os.getenv("CARGO_HOME") .. "/bin/rust-analyzer" or "rust-analyzer" },
					filetypes = { "rust" },
					settings = {
						["rust-analyzer"] = {
							cargo = { allFeatures = true },
							checkOnSave = { command = "clippy" },
						},
					},
					root_dir = lsputil.root_pattern("Cargo.toml", "rust-project.json", ".git"),
				})

				lsp.configure("zls", {
					cmd = { os.getenv("ZLS_PATH") or "zls" },
					filetypes = { "zig" },
					root_dir = lsputil.root_pattern("build.zig", ".git"),
				})

				lsp.configure("pyright", {
					cmd = { os.getenv("PYRIGHT_PATH") or "pyright-langserver", "--stdio" },
					filetypes = { "python" },
					root_dir = lsputil.root_pattern("pyproject.toml", "setup.py", ".git"),
				})
			end

			lsp.setup()
		end,
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
	{
		"mhartington/formatter.nvim",
		event = "BufWritePost",
		config = function()
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = vim.api.nvim_create_augroup("FormatAutogroup", { clear = true }),
				pattern = "*",
				command = "FormatWrite",
			})

			-- Formatter settings
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

	------------------------------------------------------------------
	-- Plugin: nvim-treesitter (シンタックスハイライト・インデント)
	------------------------------------------------------------------
	{
		"nvim-treesitter/nvim-treesitter",
		run = ":TSUpdate",
		event = "BufReadPost",
		config = function()
			local ts_configs = safe_require("nvim-treesitter.configs")
			if ts_configs then
				ts_configs.setup({
					auto_install = true,
					highlight = { enable = true },
					indent = { enable = true },
					ensure_installed = { "bash", "c", "cpp", "go", "lua", "rust", "zig", "nim", "python" },
				})
			end
		end,
	},

	------------------------------------------------------------------
	-- Plugin: lualine (ステータスライン)
	------------------------------------------------------------------
	{
		"nvim-lualine/lualine.nvim",
		event = "VimEnter",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			local lualine = safe_require("lualine")
			if lualine then
				lualine.setup({
					options = {
						theme = "auto",
						section_separators = "",
						component_separators = "|",
					},
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
		config = function()
			local comment = safe_require("Comment")
			if comment then
				comment.setup()
				local api = safe_require("Comment.api")
				if api then
					vim.keymap.set("n", "<C-c>", api.toggle.linewise.current, { desc = "Toggle comment" })
					vim.keymap.set("v", "<C-c>", api.toggle.linewise, { desc = "Toggle comment" })
				end
			end
		end,
		keys = { "<C-c>" },
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

-----------------------------------------------------------
-- 5. グローバルキーマッピング
-----------------------------------------------------------
-- Telescope を用いたファジー検索のキーマッピング
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { silent = true, noremap = true })

-----------------------------------------------------------
-- End of configuration
-----------------------------------------------------------
