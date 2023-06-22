local fn = vim.fn
local pkg_path = fn.stdpath "config" .. "/lazy"
local lazypath = pkg_path .. "/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    fn.system {
        "git",
        "clone",
        "--depth",
        "1",
        "https://github.com/folke/lazy.nvim",
        lazypath,
    }
end

vim.opt.rtp:prepend(lazypath)

local status, lazy = pcall(require, "lazy")
if not status then
    error("lazy is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath)
    return
end

lazy.setup({
    {
        "hrsh7th/nvim-cmp",
        event = "InsertEnter",
        opts = function()
            local status, cmp = pcall(require, "cmp")
            if not status then
                error("cmp is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath)
                return
            end
            local status, cmplsp = pcall(require, "cmp_nvim_lsp")
            if not status then
                error("cmp_nvim_lsp is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath)
                return
            end
            local status, lspkind = pcall(require, "lspkind")
            if not status then
                error("lspkind is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath)
                return
            end
            cmp.setup.cmdline("/", {
                mapping = cmp.mapping.preset.cmdline(),
                sources = {
                    { name = "buffer" }, --ソース類を設定
                },
            })
            cmp.setup.cmdline(":", {
                mapping = cmp.mapping.preset.cmdline(),
                sources = cmp.config.sources({
                    { name = "path" },
                }, {
                    { name = "cmdline" },
                }),
            })
            return {
                snippet = {
                    expand = function(args)
                        fn["vsnip#anonymous"](args.body)
                    end,
                },
                sources = {
                    { name = "nvim_lsp" }, --ソース類を設定
                    { name = "cmp_tabnine" },
                    { name = "vsnip" }, -- For vsnip users.
                    { name = "buffer" },
                    { name = "path" },
                    {
                        name = "look",
                        keyword_length = 2,
                        option = {
                            convert_case = true,
                            loud = true,
                            --dict = '/usr/share/dict/words'
                        },
                    },
                },
                mapping = cmp.mapping.preset.insert {
                    ["<Tab>"] = cmp.mapping.select_next_item(), --Ctrl+pで補完欄を一つ上に移動
                    ["<C-p>"] = cmp.mapping.select_prev_item(), --Ctrl+pで補完欄を一つ上に移動
                    ["<C-n>"] = cmp.mapping.select_next_item(), --Ctrl+nで補完欄を一つ下に移動
                    ["<C-l>"] = cmp.mapping.complete(),
                    ["<C-e>"] = cmp.mapping.abort(),
                    ["<C-y>"] = cmp.mapping.confirm { select = true }, --Ctrl+yで補完を選択確定
                    ["<C-b>"] = cmp.mapping.scroll_docs(-4),
                    ["<C-f>"] = cmp.mapping.scroll_docs(4),
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<CR>"] = cmp.mapping.confirm { select = true }, -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
                },
                experimental = {
                    ghost_text = false,
                },
                capabilities = cmplsp.default_capabilities(),
                formatting = {
                    format = lspkind.cmp_format {
                        mode = "symbol", -- show only symbol annotations
                        maxwidth = 50, -- prevent the popup from showing more than provided characters (e.g 50 will not show more than 50 characters)
                        ellipsis_char = "...", -- when popup menu exceed maxwidth, the truncated part would show ellipsis_char instead (must define maxwidth first)
                        before = function(entry, vim_item)
                            return vim_item
                        end,
                    },
                },
            }
        end,
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-nvim-lua",
            "hrsh7th/vim-vsnip",
            "hrsh7th/cmp-vsnip",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-cmdline",
            "hrsh7th/cmp-path",
            "onsails/lspkind.nvim",
        },
    },
    { "tzachar/cmp-tabnine", build = "./install.sh", dependencies = "hrsh7th/nvim-cmp" },
    {
        "numToStr/Comment.nvim",
        config = true,
        lazy = true,
        keys = {
            {
                "<C-_>",
                ":lua require('Comment.api').toggle.linewise.current()<CR>",
                { noremap = true, silent = true },
                desc = "",
                mode = "n",
            },
            {
                "<C-_>",
                '<ESC><CMD>lua require("Comment.api").toggle.linewise(vim.fn.visualmode())<CR>',
                { noremap = true, silent = true },
                desc = "",
                mode = "x",
            },
            {
                "<C-_>",
                ":lua require('Comment.api').toggle.linewise.current() <CR>",
                { noremap = true, silent = true },
                desc = "",
                mode = "i",
            },
        },
    },
    {
        "neovim/nvim-lspconfig",
        lazy = true,
        keys = {
            {
                "gD",
                vim.lsp.buf.declaration,
                { noremap = true, silent = true },
                desc = "Go To Declaration",
                mode = "n",
            },
            {
                "gi",
                vim.lsp.buf.implementation,
                { noremap = true, silent = true },
                desc = "Go To Implementation",
                mode = "n",
            },
            { "K", vim.lsp.buf.hover, { silent = true }, desc = "Show Info", mode = "n" },
            {
                "<leader>k",
                vim.lsp.buf.signature_help,
                { silent = true, noremap = true },
                desc = "Show Signature",
                mode = "n",
            },
            {
                "<Leader>gr",
                vim.lsp.buf.references,
                { noremap = true, silent = true },
                desc = "Go To References",
                mode = "n",
            },
            {
                "<Leader>D",
                vim.lsp.buf.type_definition,
                { noremap = true, silent = true },
                desc = "Show Type Definition",
                mode = "n",
            },
        },
    },
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        dependencies = {
            "nvim-treesitter/nvim-treesitter-textobjects",
	    {"navarasu/onedark.nvim", config = true, opts = { style = "darker"}},
        },
        opts = {
            sync_install = false,
            highlight = {
                enable = true,
                disable = {},
            },
            indent = {
                enable = true,
                disable = {},
            },
            ensure_installed = {
                "bash",
                "c",
                "cmake",
                "cpp",
                "css",
                "cuda",
                "dart",
                "dockerfile",
                "gitignore",
                "go",
                "gomod",
                "graphql",
                "help",
                "html",
                "http",
                "java",
                "javascript",
                "json",
                "json5",
                "julia",
                "kotlin",
                "llvm",
                "lua",
                "make",
                "markdown",
                "markdown_inline",
                "meson",
                "ninja",
                "nix",
                "proto",
                "python",
                "regex",
                "rego",
                "rust",
                "sql",
                "toml",
                "typescript",
                "v",
                "vim",
                "yaml",
                "zig",
            },
            autotag = {
                enable = true,
            },
        },
    },
    { "williamboman/mason.nvim", config = true, dependencies = "neovim/nvim-lspconfig" },
    {
        "williamboman/mason-lspconfig.nvim",
        opts = {
            ui = {
                icons = {
                    package_installed = "✓",
                    package_pending = "➜",
                    package_uninstalled = "✗",
                },
            },
            ensure_installed = {
                "gopls",
                "sumneko_lua",
                "dockerls",
                "yamlls",
            },
            automatic_installation = true,
        },
        config = function()
            local status, lspconfig = pcall(require, "lspconfig")
            if not status then
                error("lspconfig is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath)
                return
            end
            local status, cmplsp = pcall(require, "cmp_nvim_lsp")
            if not status then
                error("cmp_nvim_lsp is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath)
                return
            end

            local status, mason_lspconfig = pcall(require, "mason-lspconfig")
            if not status then
                error(
                    "mason_lspconfig is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath
                )
                return
            end

            local capabilities = cmplsp.default_capabilities()
            mason_lspconfig.setup_handlers {
                function(server_name)
                    local opts = {}
                    if server_name == "lua-language-server" then
                        opts.settings = {
                            Lua = {
                                diagnostics = { globals = { "vim" } },
                            },
                        }
                    elseif server_name == "gopls" then
                        opts = {
                            cmd = { "gopls", "--remote=auto" },
                            filetypes = { "go", "gomod" },
                            root_dir = lspconfig.util.root_pattern(".git", "go.mod", "go.sum", "go.work"),
                        }
                    elseif server_name == "dockerls" then
                        opts = {
                            cmd = { "docker-langserver", "--stdio" },
                            filetypes = { "Dockerfile", "dockerfile" },
                        }
                    elseif server_name == "yamlls" then
                        opts = {
                            cmd = { "yaml-language-server", "--stdio" },
                            filetypes = { "yaml", "yml" },
                        }
                    end
                    opts.capabilities = capabilities
                    lspconfig[server_name].setup(opts)
                end,
            }
        end,
        dependencies = "williamboman/mason.nvim",
    },
    { "gpanders/editorconfig.nvim" },
    {
        "glepnir/lspsaga.nvim",
        lazy = true,
        keys = {
            {
                "<leader>ca",
                "<cmd><C-U>Lspsaga range_code_action<CR>",
                { silent = true, noremap = true },
                desc = "Range Code Action",
                mode = "v",
            },
            {
                "<leader>ca",
                "<cmd>Lspsaga code_action<CR>",
                { silent = true, noremap = true },
                desc = "Code Action",
                mode = "n",
            },
            {
                "<leader>e",
                "<cmd>Lspsaga show_line_diagnostics<CR>",
                { silent = true, noremap = true },
                desc = "Show Line Diagnostics",
                mode = "n",
            },
            {
                "<Leader>[",
                "<cmd>Lspsaga diagnostic_jump_prev<CR>",
                { noremap = true, silent = true },
                desc = "Jump To The Next Diagnostics",
                mode = "n",
            },
            {
                "<Leader>]",
                "<cmd>Lspsaga diagnostic_jump_next<CR>",
                { noremap = true, silent = true },
                desc = "Jump To The Previous Diagnostics",
                mode = "n",
            },
            { "<Leader>T", "<cmd>Lspsaga open_floaterm<CR>", { silent = true }, desc = "Open Float Term", mode = "n" },
            {
                "<Leader>T",
                [[<C-\><C-n><cmd>Lspsaga close_floaterm<CR>]],
                { silent = true },
                desc = "Close Float Term",
                mode = "t",
            },
            { "gr", "<cmd>Lspsaga rename<CR>", { silent = true, noremap = true }, desc = "Rename", mode = "n" },
            { "gh", "<cmd>Lspsaga lsp_finder<CR>", { silent = true, noremap = true }, desc = "LSP Finder", mode = "n" },
            { "gd", "<cmd>Lspsaga peek_definition<CR>", { silent = true }, desc = "Peek Definition", mode = "n" },
        },
        branch = "main",
        opts = { border_style = "rounded" },
        dependencies = "neovim/nvim-lspconfig",
    },
    {
        "jose-elias-alvarez/null-ls.nvim",
        branch = "main",
        dependencies = "nvim-lua/plenary.nvim",
        config = true,
        opts = function()
            local status, null_ls = pcall(require, "null-ls")
            if not status then
                error("null-ls is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath)
                return
            end

            return {
                sources = {
                    null_ls.builtins.diagnostics.cspell.with {
                        diagnostics_postprocess = function(diagnostic)
                            diagnostic.severity = vim.diagnostic.severity["WARN"]
                        end,
                        condition = function()
                            return fn.executable "cspell" > 0
                        end,
                    },
                    null_ls.builtins.diagnostics.eslint_d.with {
                        diagnostics_format = "[eslint] #{m}\n(#{c})",
                    },
                    null_ls.builtins.diagnostics.fish,
                    null_ls.builtins.diagnostics.eslint,
                    null_ls.builtins.completion.spell,
                    null_ls.builtins.formatting.stylua,
                    null_ls.builtins.formatting.deno_fmt.with {
                        condition = function(utils)
                            return not (utils.has_file { ".prettierrc", ".prettierrc.js", "deno.json", "deno.jsonc" })
                        end,
                    },
                    null_ls.builtins.formatting.prettier.with {
                        condition = function(utils)
                            return utils.has_file { ".prettierrc", ".prettierrc.js" }
                        end,
                        prefer_local = "node_modules/.bin",
                    },
                },
            }
        end,
    },
    { "nvim-tree/nvim-web-devicons" },
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
                theme = "gruvbox-material",
                component_separators = { left = "", right = "" },
                section_separators = { left = "", right = "" },
                disabled_filetypes = { "NvimTree", "packer", "TelescopePrompt" },
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
}, {
    root = pkg_path,
})

local status, onedark = pcall(require, "onedark")
if not status then
    error "onedark colorscheme is not installed"
    return
end
onedark.load()
