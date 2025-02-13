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

-- List of languages for nvim-treesitter
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

-- List of LSP servers to ensure installed
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

-- List of development tools to ensure installed
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
	-- General plugins
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
							safe_require("mason").setup({
								ui = {
									icons = {
										package_installed = "✓",
										package_pending = "➜",
										package_uninstalled = "✗",
									},
								},
							})
						end,
					},
					{
						"williamboman/mason-lspconfig.nvim",
						config = function()
							safe_require("mason-lspconfig").setup({
								ensure_installed = lsps,
							})
						end,
					},
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
					{
						"ray-x/lsp_signature.nvim",
						event = { "InsertEnter", "BufReadPre" },
						config = function()
							safe_require("lsp_signature").setup({
								bind = true, -- This is mandatory, otherwise border config won't get registered.
								handler_opts = {
									border = "none",
								},
								padding = " ",
								toggle_key = "<C-x>",
							})
						end,
					},
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
						lua_ls = {
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
						maxwidth = 120
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
	-- Linter settings
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
				-- rust = { "clippy" },
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

-- Load onedark colorscheme
safe_require("onedark").load()

-- Customize LSP diagnostic handler
--vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.diagnostic.on_publish_diagnostics, {
--	underline = true,
--	virtual_text = {
--		spacing = 4,
--		prefix = "",
--		format = function(diagnostic, virtual_text)
--			return string.format("%s %s (%s: %s)", virtual_text, diagnostic.message, diagnostic.source, diagnostic.code)
--		end,
--	},
--	signs = true,
--	update_in_insert = false,
--})
