-- Initialize necessary paths
local fn = vim.fn
local pkg_path = fn.stdpath("config") .. "/lazy"
local lazypath = pkg_path .. "/lazy.nvim"

-- Auto-install lazy.nvim if not already installed
if not vim.loop.fs_stat(lazypath) then
    fn.system {
        "git",
        "clone",
        "--depth",
        "1",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim",
        lazypath,
    }
end

vim.opt.rtp:prepend(lazypath)
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "preview" }
vim.opt.shortmess:append("c")

local function safe_require(module_name)
    local status, module = pcall(require, module_name)
    if not status then
        vim.api.nvim_err_writeln("Error loading module: " ..
            module_name .. " is not installed. Install path: " .. pkg_path)
        return nil
    end
    return module
end

local languages = {
    "bash", "c", "cpp", "dart", "dockerfile", "go", "html", "json", "lua", "make", "markdown", "nim", "rust", "yaml",
    "zig"
}

local lsps = {
    "clangd", "gopls", "pyright", "rust_analyzer", "zls"
}

safe_require("lazy").setup({
    -- General plugins
    {
        "neovim/nvim-lspconfig",
        event = "BufReadPre",
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
        },
        config = function()
            safe_require("mason").setup()
            safe_require("mason-lspconfig").setup {
                ensure_installed = lsps
            }
            local lspconfig = safe_require("lspconfig")
            local on_attach = function(client, bufnr)
                vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
            end
            for _, server in ipairs(lsps) do
                lspconfig[server].setup { on_attach = on_attach }
            end
        end,
    },
    {
        "hrsh7th/nvim-cmp",
        event = { "InsertEnter", "CmdlineEnter" },
        dependencies = {
            { "neovim/nvim-lspconfig",                event = "InsertEnter" },
            {
                "L3MON4D3/LuaSnip",
                build = "make install_jsregexp",
                event = "InsertEnter",
                config = function()
                    safe_require('luasnip').config.set_config {
                        history = true,
                        updateevents = "TextChanged,TextChangedI",
                    }
                    safe_require("luasnip.loaders.from_vscode").lazy_load()
                end,
            },
            { "hrsh7th/cmp-buffer",                   event = "InsertEnter" },
            { "hrsh7th/cmp-calc",                     event = "InsertEnter" },
            { "hrsh7th/cmp-cmdline",                  event = "ModeChanged" },
            { "hrsh7th/cmp-nvim-lsp",                 event = "InsertEnter" },
            { "hrsh7th/cmp-nvim-lsp-document-symbol", event = "InsertEnter" },
            { "hrsh7th/cmp-nvim-lsp-signature-help",  event = "InsertEnter" },
            { "hrsh7th/cmp-nvim-lua",                 event = "InsertEnter" },
            { "hrsh7th/cmp-path",                     event = "InsertEnter" },
            { "ray-x/cmp-treesitter",                 event = "InsertEnter" },
            { "petertriho/cmp-git",                   config = true,        event = "InsertEnter", dependencies = { 'nvim-lua/plenary.nvim' } },
            { "onsails/lspkind.nvim",                 event = "InsertEnter" },
            { "rafamadriz/friendly-snippets",         event = "InsertEnter" },
            { "saadparwaiz1/cmp_luasnip",             event = "InsertEnter" },
        },
        config = function()
            local cmp = safe_require("cmp")
            local luasnip = safe_require("luasnip")
            local lspkind = safe_require("lspkind")
            local capabilities = safe_require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol
            .make_client_capabilities())

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
                            require("copilot.suggestion").accept()
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
                    { name = "copilot",                group_index = 2 },
                    -- Other Sources
                    { name = "nvim_lsp",               group_index = 2 },
                    { name = "nvim_lsp_signature_help" },
                    { name = "path",                   group_index = 2 },
                    { name = "buffer",                 get_bufnrs = vim.api.nvim_list_bufs, group_index = 2 },
                    { name = "luasnip",                group_index = 2 },
                    {
                        name = "look",
                        keyword_length = 2,
                        option = {
                            convert_case = true,
                            loud = true,
                            -- dict = '/usr/share/dict/words'
                        },
                    },
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
                    completion = cmp.config.window.bordered {
                        border = "single",
                        col_offset = 0,
                        side_padding = 0,
                    },
                    documentation = cmp.config.window.bordered {
                        winhiglight = "NormalFloat:CompeDocumentation,FloatBorder:TelescopeBorder",
                    },
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
                    })
                },
                experimental = {
                    ghost_text = false,
                    native_menu = false,
                },
            })
        end,
    },
    {
        "nvim-treesitter/nvim-treesitter",
        event = "BufReadPost",
        run = ":TSUpdate",
        dependencies = {
            { "navarasu/onedark.nvim", config = true, opts = { style = "darker" } },
        },
        config = function()
            safe_require("nvim-treesitter.configs").setup {
                auto_install = true,
                sync_install = false,
                ensure_installed = languages,
                highlight = {
                    enable = true,
                },
                indent = {
                    enable = true,
                },
                autotag = {
                    enable = true,
                },
            }
        end,
    },
    {
        "zbirenbaum/copilot.lua",
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
                server_opts_overrides = {},
                on_status_update = safe_require("lualine").refresh,
            })
        end,
    },
    {
        "zbirenbaum/copilot-cmp",
        after = { "copilot.lua", "nvim-cmp" },
        event = { "InsertEnter", "LspAttach" },
        fix_pairs = true,
        config = true,
    },
    {
        "numToStr/Comment.nvim",
        event = "BufReadPost",
        config = function()
            safe_require("Comment").setup()
        end,
    },
    {
        "nvim-lualine/lualine.nvim",
        event = "VimEnter",
        dependencies = {
            "nvim-tree/nvim-web-devicons",
            "SmiteshP/nvim-navic",
        },
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
                    function()
                        local navic = safe_require("nvim-navic")
                        return {
                            function()
                                return navic.get_location()
                            end,
                            cond = function()
                                return navic.is_available()
                            end,
                        }
                    end,
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
        config = true,
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
                        fn.jobstart("open -a skim " .. '"' .. fn.expand "%" .. '"')
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
        "windwp/nvim-autopairs",
        opts = {
            disable_filetype = { "TelescopePrompt", "vim" },
        },
        config = true,
    },
    {
        "lewis6991/gitsigns.nvim",
        event = "BufReadPost",
        config = function()
            safe_require("gitsigns").setup()
        end,
    },
    -- Language specific plugins and configurations
    {
        "fatih/vim-go",
        ft = { "go" },
        config = function()
            vim.g.go_fmt_command = "goimports"
        end
    },
    {
        "rust-lang/rust.vim",
        ft = { "rust" },
        config = function()
            vim.g.rustfmt_autosave = 1
        end
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
        end
    },
}, {
    root = pkg_path,
})


safe_require("onedark").load()
