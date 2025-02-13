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
