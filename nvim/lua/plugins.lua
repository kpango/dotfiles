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
	    local coq = safe_require("coq")
            local on_attach = function(client, bufnr)
                vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
            end
            for _, server in ipairs(lsps) do
                lspconfig[server].setup(coq.lsp_ensure_capabilities())
            end
        end,
    },
    -- Replace nvim-cmp with coq_nvim
    {
        "ms-jpq/coq_nvim",
        branch = "coq",
        event = "InsertEnter",
	dependencies =  { "ms-jpq/coq.artifacts", branch = "artifacts" },
        run = ":COQdeps",
        config = function()
            vim.g.coq_settings = {
                auto_start = true,
                clients = {
                    lsp = {
                        enabled = true,
                        weight_adjust = 1.5,
                    },
                    snippets = {
                        enabled = true,
                        user_path = "~/.config/nvim/snippets",
                    },
                    copilot = {
                        enabled = true,
                        weight_adjust = 2.0,
                    },
                },
                keymap = {
                    jump_to_mark = "<C-y>",
                    pre_select = true,
                },
                display = {
                    ghost_text = {
                        enabled = true,
                        context = { "", "<CR>" },
                    },
                },
            }
        end,
    },
    {
        "ms-jpq/coq.thirdparty",
        branch = "3p",
        config = function()
            safe_require("coq_3p") {
                { src = "copilot", short_name = "COP", accept_key = "<C-f>" },
            }
        end,
        after = { "coq_nvim", "copilot.lua" },
    },
    -- Treesitter configuration
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
    -- Copilot configuration
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
    -- Other plugins remain unchanged
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
        config = true,
        opts = {
            signs = {
                add          = { text = '┃' },
                change       = { text = '┃' },
                delete       = { text = '_' },
                topdelete    = { text = '‾' },
                changedelete = { text = '~' },
                untracked    = { text = '┆' },
            },
            signcolumn = true, -- Toggle with :Gitsigns toggle_signs
            numhl = false,     -- Toggle with :Gitsigns toggle_numhl
            linehl = false,    -- Toggle with :Gitsigns toggle_linehl
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
            status_formatter = nil,  -- Use default
            max_file_length = 40000, -- Disable if file is longer than this (in lines)
            preview_config = {
                -- Options passed to nvim_open_win
                border = "single",
                style = "minimal",
                relative = "cursor",
                row = 0,
                col = 1,
            },
        },
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
    -- code formatter setting
    {
        "mhartington/formatter.nvim",
        event = "BufWritePost",
        config = function()
            -- 保存時に自動フォーマットを有効にする
            vim.api.nvim_exec([[
                augroup FormatAutogroup
                    autocmd!
                    autocmd BufWritePost * FormatWrite
                augroup END
            ]], true)

            -- フォーマッタの設定
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
                                args = { "-i", "4" },
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
    -- Debug Adapter Protocol
    {
        'mfussenegger/nvim-dap',
        ft = { "c", "cpp", "rust", "go" },
        config = function()
            local dap = safe_require('dap')
            dap.adapters.lldb = {
                type = 'executable',
                command = '/usr/bin/lldb-vscode', -- adjust as needed
                name = 'lldb'
            }
            dap.configurations.cpp = {
                {
                    name = 'Launch',
                    type = 'lldb',
                    request = 'launch',
                    program = function()
                        return fn.input('Path to executable: ', fn.getcwd() .. '/', 'file')
                    end,
                    cwd = '${workspaceFolder}',
                    stopOnEntry = false,
                    args = {},

                    runInTerminal = false,
                },
            }
            dap.configurations.c = dap.configurations.cpp
        end
    },

}, {
    root = pkg_path,
})

safe_require("onedark").load()
