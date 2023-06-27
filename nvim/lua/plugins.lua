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
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "preview" }
vim.opt.shortmess = vim.opt.shortmess + { c = true }

local function safe_require(module_name)
    local status, module = pcall(require, module_name)
    if not status then
        error(module_name .. " is not installed install_path: " .. pkg_path .. " packpath: " .. vim.o.packpath)
        return nil
    end
    return module
end

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
            local cmp = safe_require "cmp"
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
                sources = cmp.config.sources {
                    { name = "nvim_lsp", keyword_length = 3 },
                    { name = "luasnip" },
                    { name = "cmp_tabnine" },
                    { name = "nvim_lua" },
                },
            })
            return {
                flags = {
                    debounce_text_changes = 150,
                },
                snippet = {
                    expand = function(args)
                        safe_require("luasnip").lsp_expand(args.body)
                    end,
                },
                window = {
                    completion = cmp.config.window.bordered {
                        border = "single",
                        col_offset = -3,
                        side_padding = 0,
                    },
                    documentation = cmp.config.window.bordered {
                        border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
                        winhiglight = "NormalFloat:CompeDocumentation,FloatBorder:TelescopeBorder",
                    },
                },
                sources = cmp.config.sources {
                    {
                        { name = "nvim_lsp", keyword_length = 3 },
                        { name = "luasnip" },
                        { name = "cmp_tabnine" },
                        { name = "nvim_lsp_signature_help" },
                    },
                    { name = "buffer", get_bufnrs = vim.api.nvim_list_bufs, keyword_length = 2 },
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
                    { name = "cmdline" },
                    { name = "git" },
                },
                mapping = cmp.mapping.preset.insert {
                    -- ["<Tab>"] = cmp.mapping.select_next_item(), --Ctrl+pで補完欄を一つ上に移動
                    ["<C-p>"] = cmp.mapping.select_prev_item(), --Ctrl+pで補完欄を一つ上に移動
                    ["<C-n>"] = cmp.mapping.select_next_item(), --Ctrl+nで補完欄を一つ下に移動
                    ["<C-l>"] = cmp.mapping.complete(),
                    ["<C-e>"] = cmp.mapping.abort(),
                    ["<C-y>"] = cmp.mapping.confirm { select = true }, --Ctrl+yで補完を選択確定
                    ["<C-b>"] = cmp.mapping.scroll_docs(-4),
                    ["<C-f>"] = cmp.mapping.scroll_docs(4),
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<CR>"] = cmp.mapping.confirm { select = true },
                },
                experimental = {
                    ghost_text = false,
                },
                on_attach = on_attach,
                capabilities = capabilities,
                formatting = {
                    format = safe_require("lspkind").cmp_format {
                        mode = "symbol",
                        maxwidth = 50,
                        ellipsis_char = "...",
                        before = function(entry, vim_item)
                            return vim_item
                        end,
                    },
                },
            }
        end,
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
                    vim.lsp.buf.format { async = true }
                end,
                mode = "n",
                desc = "",
                noremap = true,
                silent = true,
            },
            {
                "<space>e",
                vim.lsp.diagnostic.show_line_diagnostics,
                mode = "n",
                desc = "",
                noremap = true,
                silent = true,
            },
            {
                "<space>q",
                vim.lsp.diagnostic.set_loclist,
                mode = "n",
                desc = "",
                noremap = true,
                silent = true,
            },
            {
                "[d",
                vim.lsp.diagnostic.goto_prev,
                mode = "n",
                desc = "",
                noremap = true,
                silent = true,
            },
            {
                "]d",
                vim.lsp.diagnostic.goto_next,
                mode = "n",
                desc = "",
                noremap = true,
                silent = true,
            },
        },
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
            { "petertriho/cmp-git", config = ture, event = "InsertEnter" },
            { "octaltree/cmp-look", config = ture, event = "InsertEnter" },
            {
                "onsails/lspkind.nvim",
                event = "InsertEnter",
                config = function(_, opts)
                    safe_require("lspkind").init(opts)
                end,
                opts = {
                    mode = "symbol_text",
                    preset = "codicons",
                    menu = {
                        nvim_lua = "[API]",
                        nvim_lsp = "[LSP]",
                        cmp_tabnine = "[TN]",
                        luasnip = "[LSN]",
                        buffer = "[Buffer]",
                        path = "[Path]",
                        look = "[LK]",
                    },
                    symbol_map = {
                        Array = "",
                        Boolean = "",
                        Key = "",
                        Namespace = "",
                        Null = "",
                        Number = "",
                        Object = "",
                        Package = "",
                        String = "",
                        Text = " ",
                        Method = " ",
                        Function = " ",
                        Constructor = " ",
                        Field = " ",
                        Variable = " ",
                        Class = " ",
                        Interface = " ",
                        Module = " ",
                        Property = " ",
                        Unit = " ",
                        Value = " ",
                        Enum = " ",
                        Keyword = " ",
                        Snippet = " ",
                        Color = " ",
                        File = " ",
                        Reference = " ",
                        Folder = " ",
                        EnumMember = " ",
                        Constant = " ",
                        Struct = " ",
                        Event = " ",
                        Operator = " ",
                        TypeParameter = " ",
                    },
                },
            },
            { "rafamadriz/friendly-snippets", event = "InsertEnter" },
            { "saadparwaiz1/cmp_luasnip", event = "InsertEnter" },
        },
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
	event = "VeryLazy",
    },
    {
        "github/copilot.vim",
        lazy = false,
        -- config = function()
        --     vim.g.copilot_no_tab_map = true
        -- end,
        keys = {
            {
                "<C-i>",
                'copilot#Accept("")',
                replace_keycodes = false,
                mode = "i",
                desc = "Accept Copilot suggestion",
                expr = true,
                silent = true,
            },
        },
    },
    {
        "numToStr/Comment.nvim",
        config = true,
        lazy = true,
        opts = {
            ignore = "^$",
        },
        keys = {
            {
                "<C-c>",
                ":lua require('Comment.api').toggle.linewise.current()<CR>",
                desc = "",
                mode = "n",
                noremap = true,
                silent = true,
            },
            {
                "<C-c>",
                '<ESC><CMD>lua require("Comment.api").toggle.linewise(vim.fn.visualmode())<CR>',
                desc = "",
                mode = "x",
                noremap = true,
                silent = true,
            },
            {
                "<C-c>",
                ":lua require('Comment.api').toggle.linewise.current() <CR>",
                desc = "",
                mode = "i",
                noremap = true,
                silent = true,
            },
        },
    },
    {
        "neovim/nvim-lspconfig",
        event = { "InsertEnter", "CmdlineEnter" },
        lazy = true,
        keys = function()
            local opts = { noremap = true, silent = true }
            return {
                {
                    "gD",
                    vim.lsp.buf.declaration,
                    opts,
                    desc = "Go To Declaration",
                    mode = "n",
                    silent = true,
                    noremap = true,
                },
                {
                    "gi",
                    vim.lsp.buf.implementation,
                    opts,
                    desc = "Go To Implementation",
                    mode = "n",
                    silent = true,
                    noremap = true,
                },
                {
                    "<leader>k",
                    vim.lsp.buf.signature_help,
                    opts,
                    desc = "Show Signature",
                    mode = "n",
                    silent = true,
                    noremap = true,
                },
                {
                    "<Leader>gr",
                    vim.lsp.buf.references,
                    opts,
                    desc = "Go To References",
                    mode = "n",
                    silent = true,
                    noremap = true,
                },
                {
                    "<Leader>D",
                    vim.lsp.buf.type_definition,
                    opts,
                    desc = "Show Type Definition",
                    mode = "n",
                    silent = true,
                    noremap = true,
                },
                {
                    "K",
                    vim.lsp.buf.hover,
                    desc = "Show Info",
                    mode = "n",
                    silent = true,
                    noremap = true,
                },
            }
        end,
    },
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        dependencies = {
            "nvim-treesitter/nvim-treesitter-textobjects",
            { "navarasu/onedark.nvim", config = true, opts = { style = "darker" } },
        },
        config = function(_, opts)
            local ntsi = safe_require "nvim-treesitter.install"
            ntsi.compilers = { "clang" }
            ntsi.update { with_sync = true }
            safe_require("nvim-treesitter.configs").setup(opts)
        end,
        opts = {
            auto_install = true,
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
    {
        "williamboman/mason-lspconfig.nvim",
        event = "InsertEnter",
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
                "dockerls",
                "rust-analyzer",
                "yamlls",
            },
            automatic_installation = true,
        },
        config = function(_, opts)
            local lspconfig = safe_require "lspconfig"
            local mason_lspconfig = safe_require "mason-lspconfig"
            local capabilities =
                safe_require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
            mason_lspconfig.setup(opts)
            mason_lspconfig.setup_handlers {
                function(server_name)
                    local opts = {
                        settings = {
                            solargraph = {
                                diagnostics = false,
                            },
                        },
                    }
                    if server_name == "lua-language-server" then
                        opts.settings = {
                            Lua = {
                                runtime = {
                                    version = "LuaJIT",
                                },
                                diagnostics = {
                                    globals = {
                                        "vim",
                                        "require",
                                    },
                                },
                                workspace = {
                                    library = vim.api.nvim_get_runtime_file("", true),
                                },
                                telemetry = {
                                    enable = false,
                                },
                            },
                        }
                    elseif server_name == "gopls" then
                        opts = {
                            cmd = { "gopls", "serve", "-rpc.trace", "--debug=localhost:6060" },
                            -- cmd = { "gopls", "--remote=auto" },
                            filetypes = { "go", "gomod", "gowork" },
                            root_dir = lspconfig.util.root_pattern(".git", "go.mod", "go.sum", "go.work"),
                            settings = {
                                gopls = {
                                    analyses = {
                                        unusedparams = true,
                                    },
                                    staticcheck = true,
                                },
                            },
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
        dependencies = {
            "williamboman/mason.nvim",
            cmd = { "Mason", "MasonInstall", "MasonInstallAll", "MasonUninstall", "MasonUninstallAll", "MasonLog" },
            event = "InsertEnter",
            config = true,
            dependencies = "neovim/nvim-lspconfig",
        },
    },
    { "gpanders/editorconfig.nvim" },
    {
        "glepnir/lspsaga.nvim",
        lazy = true,
        keys = {
            {
                "<leader>ca",
                "<cmd><C-U>Lspsaga range_code_action<CR>",
                desc = "Range Code Action",
                mode = "v",
                silent = true,
                noremap = true,
            },
            {
                "<leader>ca",
                "<cmd>Lspsaga code_action<CR>",
                desc = "Code Action",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "<leader>e",
                "<cmd>Lspsaga show_line_diagnostics<CR>",
                desc = "Show Line Diagnostics",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "<Leader>[",
                "<cmd>Lspsaga diagnostic_jump_prev<CR>",
                desc = "Jump To The Next Diagnostics",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "<Leader>]",
                "<cmd>Lspsaga diagnostic_jump_next<CR>",
                desc = "Jump To The Previous Diagnostics",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "<Leader>T",
                "<cmd>Lspsaga open_floaterm<CR>",
                desc = "Open Float Term",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "<Leader>T",
                [[<C-\><C-n><cmd>Lspsaga close_floaterm<CR>]],
                desc = "Close Float Term",
                mode = "t",
                silent = true,
                noremap = true,
            },
            { "gr", "<cmd>Lspsaga rename<CR>", desc = "Rename", mode = "n", silent = true, noremap = true },
            {
                "gh",
                "<cmd>Lspsaga lsp_finder<CR>",
                desc = "LSP Finder",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "gd",
                "<cmd>Lspsaga peek_definition<CR>",
                desc = "Peek Definition",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "gp",
                "<Cmd>Lspsaga preview_definition<CR>",
                desc = "Preview Definition",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "<C-j>",
                "<Cmd>Lspsaga diagnostic_jump_next<CR>",
                desc = "",
                mode = "n",
                silent = true,
                noremap = true,
            },
            { "K", "<Cmd>Lspsaga hover_doc<CR>", desc = "", mode = "n", silent = true, noremap = true },
            {
                "<C-k>",
                "<Cmd>Lspsaga signature_help<CR>",
                desc = "",
                mode = "i",
                silent = true,
                noremap = true,
            },
        },
        branch = "main",
        opts = { border_style = "rounded" },
        dependencies = "neovim/nvim-lspconfig",
    },
    {
        "jose-elias-alvarez/null-ls.nvim",
        branch = "main",
        dependencies = {
            "nvim-lua/plenary.nvim",
            {
                "jay-babu/mason-null-ls.nvim",
                opts = {
                    handlers = {},
                    ensure_installed = {
                        "cspell",
                        "stylua",
                        "jsonlint",
                        "markdownlint",
                        "prettierd",
                        "shellcheck",
                        "sql_formatter",
                        "yamlfmt",
                        "beautysh",
                        "black",
                        -- "luacheck",
                        "yamllint",
                    },
                    automatic_setup = true,
                    automatic_installation = true,
                },
                config = true,
            },
        },
        config = true,
        opts = function()
            local null_ls = safe_require "null-ls"
            return {
                diagnostics_format = "[#{s}] #{m}\n(#{c})",
                sources = {
                    null_ls.builtins.code_actions.cspell,
                    null_ls.builtins.code_actions.eslint_d,
                    null_ls.builtins.code_actions.shellcheck,
                    null_ls.builtins.code_actions.gitsigns,

                    null_ls.builtins.completion.spell,
                    null_ls.builtins.completion.tags,

                    null_ls.builtins.diagnostics.cspell.with {
                        diagnostics_postprocess = function(diagnostic)
                            diagnostic.severity = vim.diagnostic.severity["WARN"]
                        end,
                        condition = function()
                            return fn.executable "cspell" > 0
                        end,
                    },
                    null_ls.builtins.diagnostics.dotenv_linter,
                    null_ls.builtins.diagnostics.eslint,
                    null_ls.builtins.diagnostics.eslint_d.with { diagnostics_format = "[eslint] #{m}\n(#{c})" },
                    null_ls.builtins.diagnostics.fish,
                    null_ls.builtins.diagnostics.golangci_lint,
                    null_ls.builtins.diagnostics.hadolint,
                    null_ls.builtins.diagnostics.jsonlint,
                    -- null_ls.builtins.diagnostics.luacheck,
                    null_ls.builtins.diagnostics.markdownlint,
                    null_ls.builtins.diagnostics.protoc_gen_lint,
                    null_ls.builtins.diagnostics.shellcheck,
                    null_ls.builtins.diagnostics.yamllint,
                    null_ls.builtins.diagnostics.zsh,

                    null_ls.builtins.formatting.black,
                    null_ls.builtins.formatting.gofumpt,
                    null_ls.builtins.formatting.goimports,
                    null_ls.builtins.formatting.golines,
                    null_ls.builtins.formatting.json_tool,
                    null_ls.builtins.formatting.markdownlint,
                    null_ls.builtins.formatting.prettierd,
                    null_ls.builtins.formatting.prismaFmt,
                    null_ls.builtins.formatting.rustfmt,
                    null_ls.builtins.formatting.shfmt,
                    null_ls.builtins.formatting.stylua,
                    null_ls.builtins.formatting.yamlfix,
                    null_ls.builtins.formatting.yamlfmt,
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
    {
        "akinsho/bufferline.nvim",
        version = "*",
        dependencies = "nvim-tree/nvim-web-devicons",
        config = true,
        keys = {
            {
                "<Tab>",
                "<Cmd>BufferLineCycleNext<CR>",
                desc = "",
                mode = "n",
                silent = true,
                noremap = true,
            },
            {
                "<S-Tab>",
                "<Cmd>BufferLineCyclePrev<CR>",
                desc = "",
                mode = "n",
                silent = true,
                noremap = true,
            },
        },
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
                    {
                        function()
                            return safe_require("nvim-navic").get_location()
                        end,
                        cond = function()
                            return safe_require("nvim-navic").is_available()
                        end,
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
    {
        "nathom/filetype.nvim",
        lazy = false,
        config = true,
        opts = {
            overrides = {
                extensions = {},
                literal = {},
                complex = {
                    [".*git/config"] = "gitconfig", -- Included in the plugin
                },
                function_extensions = {
                    ["cpp"] = function()
                        vim.bo.filetype = "cpp"
                        vim.bo.cinoptions = vim.bo.cinoptions .. "L0"
                    end,
                    ["pdf"] = function()
                        vim.bo.filetype = "pdf"
                        vim.fn.jobstart("open -a skim " .. '"' .. vim.fn.expand "%" .. '"')
                    end,
                },
                function_literal = {
                    Brewfile = function()
                        vim.cmd "syntax off"
                    end,
                },
                function_complex = {
                    ["*.math_notes/%w+"] = function()
                        vim.cmd "iabbrev $ $$"
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
            signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
            numhl = false, -- Toggle with `:Gitsigns toggle_numhl`
            linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
            word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
            watch_gitdir = {
                interval = 1000,
                follow_files = true,
            },
            attach_to_untracked = true,
            current_line_blame = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
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
            yadm = {
                enable = false,
            },
        },
        keys = function()
            local gs = safe_require "gitsigns"
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
                        gs.blame_line { full = true }
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
                        gs.diffthis "~"
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
        "SmiteshP/nvim-navic",
        dependencies = "neovim/nvim-lspconfig",
        config = true,
        opts = {
            lsp = {
                auto_attach = true,
            },
            icons = {
                File = " ",
                Module = " ",
                Namespace = " ",
                Package = " ",
                Class = " ",
                Method = " ",
                Property = " ",
                Field = " ",
                Constructor = " ",
                Enum = "練",
                Interface = "練",
                Function = " ",
                Variable = " ",
                Constant = " ",
                String = " ",
                Number = " ",
                Boolean = "◩ ",
                Array = " ",
                Object = " ",
                Key = " ",
                Null = "ﳠ ",
                EnumMember = " ",
                Struct = " ",
                Event = " ",
                Operator = " ",
                TypeParameter = " ",
            },
            highlight = true,
            separator = " > ",
            depth_limit = 0,
            depth_limit_indicator = "..",
        },
    },
    {
        "windwp/nvim-autopairs",
        config = true,
    },
}, {
    root = pkg_path,
})

safe_require("onedark").load()

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
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
