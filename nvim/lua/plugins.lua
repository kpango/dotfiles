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
        "hrsh7th/nvim-cmp",
        event = { "InsertEnter", "CmdlineEnter" },
        opts = function()
            local cmp = safe_require "cmp"
            local cmplsp = safe_require "cmp_nvim_lsp"
            local lspkind = safe_require "lspkind"
            cmp.setup.cmdline({ "/", "?" }, {
                mapping = cmp.mapping.preset.cmdline(),
                sources = {
                    { name = "buffer" },
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
                    { name = "buffer" },
                }),
            })
            cmp.setup.filetype("lua", {
                sources = cmp.config.sources {
                    { name = "nvim_lsp" },
                    { name = "luasnip" },
                    { name = "cmp_tabnine" },
                    { name = "nvim_lua" },
                },
            })
            return {
                snippet = {
                    expand = function(args)
                        safe_require("luasnip").lsp_expand(args.body)
                    end,
                },
                window = {
                    completion = cmp.config.window.bordered {
                        border = "single",
                    },
                    documentation = cmp.config.window.bordered {
                        border = "single",
                    },
                },
                sources = {
                    {
                        { name = "nvim_lsp" },
                        { name = "luasnip" },
                        { name = "cmp_tabnine" },
                        { name = "nvim_lsp_signature_help" },
                    },
                    { name = "buffer", keyword_length = 2 },
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
                capabilities = cmplsp.default_capabilities(),
                formatting = {
                    format = lspkind.cmp_format {
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
            { "petertriho/cmp-git", config = ture, event = "InsertEnter" },
            { "onsails/lspkind.nvim", event = "InsertEnter" },
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
    },
    {
        "github/copilot.vim",
        lazy = false,
        config = function()
            vim.g.copilot_no_tab_map = true
            vim.api.nvim_set_keymap("i", "<C-i>", 'copilot#Accept("<CR>")', { silent = true, expr = true })
        end,
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
                },
                {
                    "gi",
                    vim.lsp.buf.implementation,
                    opts,
                    desc = "Go To Implementation",
                    mode = "n",
                },
                {
                    "<leader>k",
                    vim.lsp.buf.signature_help,
                    opts,
                    desc = "Show Signature",
                    mode = "n",
                },
                {
                    "<Leader>gr",
                    vim.lsp.buf.references,
                    opts,
                    desc = "Go To References",
                    mode = "n",
                },
                {
                    "<Leader>D",
                    vim.lsp.buf.type_definition,
                    opts,
                    desc = "Show Type Definition",
                    mode = "n",
                },
                { "K", vim.lsp.buf.hover, { silent = true }, desc = "Show Info", mode = "n" },
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
    {
        "williamboman/mason.nvim",
        cmd = { "Mason", "MasonInstall", "MasonInstallAll", "MasonUninstall", "MasonUninstallAll", "MasonLog" },
        event = "InsertEnter",
        config = true,
        dependencies = "neovim/nvim-lspconfig",
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
                "sumneko_lua",
                "dockerls",
                "yamlls",
            },
            automatic_installation = true,
        },
        config = function()
            local lspconfig = safe_require "lspconfig"
            local cmplsp = safe_require "cmp_nvim_lsp"
            local mason_lspconfig = safe_require "mason-lspconfig"
            local capabilities = cmplsp.default_capabilities()
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
            {
                "gp",
                "<Cmd>Lspsaga preview_definition<CR>",
                { noremap = true, silent = true },
                desc = "Preview Definition",
                mode = "n",
            },
            {
                "<C-j>",
                "<Cmd>Lspsaga diagnostic_jump_next<CR>",
                { noremap = true, silent = true },
                desc = "",
                mode = "n",
            },
            { "K", "<Cmd>Lspsaga hover_doc<CR>", { noremap = true, silent = true }, desc = "", mode = "n" },
            { "<C-k>", "<Cmd>Lspsaga signature_help<CR>", { noremap = true, silent = true }, desc = "", mode = "i" },
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
            "jay-babu/mason-null-ls.nvim",
        },
        config = true,
        opts = function()
            local null_ls = safe_require "null-ls"
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
                    -- null_ls.builtins.diagnostics.luacheck,
                    null_ls.builtins.completion.spell,
                    null_ls.builtins.diagnostics.eslint,
                    null_ls.builtins.diagnostics.fish,
                    null_ls.builtins.diagnostics.golangci_lint,
                    null_ls.builtins.diagnostics.hadolint,
                    null_ls.builtins.diagnostics.protoc_gen_lint,
                    null_ls.builtins.formatting.gofumpt,
                    null_ls.builtins.formatting.rustfmt,
                    null_ls.builtins.formatting.goimports,
                    null_ls.builtins.formatting.golines,
                    null_ls.builtins.formatting.stylua,
                    null_ls.builtins.formatting.yamlfix,
                    null_ls.builtins.formatting.yamlfmt,
                    null_ls.builtins.formatting.shfmt,
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
        keys = {
            {
                "<Tab>",
                "<Cmd>BufferLineCycleNext<CR>",
                { silent = true, noremap = true },
                desc = "",
                mode = "n",
            },
            {
                "<S-Tab>",
                "<Cmd>BufferLineCyclePrev<CR>",
                { silent = true, noremap = true },
                desc = "",
                mode = "n",
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
            on_attach = function(bufnr)
                local gs = package.loaded.gitsigns
                local function map(mode, l, r, opts)
                    opts = opts or {}
                    opts.buffer = bufnr
                    vim.keymap.set(mode, l, r, opts)
                end
                map("n", "]c", function()
                    if vim.wo.diff then
                        return "]c"
                    end
                    vim.schedule(function()
                        gs.next_hunk()
                    end)
                    return "<Ignore>"
                end, { expr = true })

                map("n", "[c", function()
                    if vim.wo.diff then
                        return "[c"
                    end
                    vim.schedule(function()
                        gs.prev_hunk()
                    end)
                    return "<Ignore>"
                end, { expr = true })
                map({ "n", "v" }, "<leader>hs", ":Gitsigns stage_hunk<CR>")
                map({ "n", "v" }, "<leader>hr", ":Gitsigns reset_hunk<CR>")
                map("n", "<leader>hS", gs.stage_buffer)
                map("n", "<leader>hu", gs.undo_stage_hunk)
                map("n", "<leader>hR", gs.reset_buffer)
                map("n", "<leader>hp", gs.preview_hunk)
                map("n", "<leader>hb", function()
                    gs.blame_line { full = true }
                end)
                map("n", "<leader>tb", gs.toggle_current_line_blame)
                map("n", "<leader>hd", gs.diffthis)
                map("n", "<leader>hD", function()
                    gs.diffthis "~"
                end)
                map("n", "<leader>td", gs.toggle_deleted)
                map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>")
            end,
        },
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
}, {
    root = pkg_path,
})

safe_require("onedark").load()
