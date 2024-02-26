local fn = vim.fn
local stdpath = fn.stdpath "config"
local packer_path = stdpath .. "/site"
local install_path = packer_path .. "/pack/packer/opt/packer.nvim"
vim.o.packpath = vim.o.packpath .. "," .. packer_path

if fn.empty(fn.glob(install_path)) > 0 then
    packer_bootstrap = fn.system {
        "git",
        "clone",
        "--depth",
        "1",
        "https://github.com/wbthomason/packer.nvim",
        install_path,
    }
end

vim.api.nvim_command "packadd packer.nvim"

local status, packer = pcall(require, "packer")
if not status then
    error("Packer is not installed install_path: " .. install_path .. " packpath: " .. vim.o.packpath)
    return
end

local status, util = pcall(require, "packer.util")
if not status then
    error("Packer util is not installed install_path: " .. install_path)
    return
end

packer.init {
    auto_clean = true, -- During sync(), remove unused plugins
    auto_reload_compiled = true, -- Automatically reload the compiled file after creating it.
    autoremove = true, -- Remove disabled or unused plugins without prompting the user
    compile_on_sync = true, -- During sync(), run packer.compile()
    compile_path = util.join_paths(stdpath, "plugin", "packer_compiled.lua"),
    disable_commands = false, -- Disable creating commands
    ensure_dependencies = true, -- Should packer install plugin dependencies?
    max_jobs = nil, -- Limit the number of simultaneous jobs. nil means no limit
    opt_default = false, -- Default to using opt (as opposed to start) plugins
    package_root = util.join_paths(stdpath, "site", "pack"),
    plugin_package = "packer", -- The default package for plugins
    snapshot = nil, -- Name of the snapshot you would like to load at startup
    -- snapshot_path = util.join_paths(stdpath 'cache', 'packer.nvim'), -- Default save directory for snapshots
    transitive_disable = true, -- Automatically disable dependencies f disabled plugins
    transitive_opt = true, -- Make dependencies of opt plugins also opt by default
    git = {
        cmd = "git", -- The base command for git operations
        subcommands = { -- Format strings for git subcommands
            update = "pull --ff-only --progress --rebase=false",
            install = "clone --depth %i --no-single-branch --progress",
            fetch = "fetch --depth 999999 --progress",
            checkout = "checkout %s --",
            update_branch = "merge --ff-only @{u}",
            current_branch = "branch --show-current",
            diff = "log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD",
            diff_fmt = "%%h %%s (%%cr)",
            get_rev = "rev-parse --short HEAD",
            get_msg = "log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1",
            submodules = "submodule update --init --recursive --progress",
        },
        depth = 1, -- Git clone depth
        clone_timeout = 60, -- Timeout, in seconds, for git clones
        default_url_format = "https://github.com/%s", -- Lua format string used for 'aaa/bbb' style plugins
    },
    display = {
        non_interactive = false, -- If true, disable display windows for all operations
        open_fn = function() -- An optional function to open a window for packer's display
            return util.float { border = "single" }
        end,
        open_cmd = "65vnew \\[packer\\]", -- An optional command to open a window for packer's display
        working_sym = "⟳", -- The symbol for a plugin being installed/updated
        error_sym = "✗", -- The symbol for a plugin with an error in installation/updating
        done_sym = "✓", -- The symbol for a plugin which has completed installation/updating
        removed_sym = "-", -- The symbol for an unused plugin which was removed
        moved_sym = "→", -- The symbol for a plugin which was moved (e.g. from opt to start)
        header_sym = "━", -- The symbol for the header line in packer's display
        show_all_info = true, -- Should packer show all update details automatically?
        prompt_border = "double", -- Border style of prompt popups.
        keybindings = { -- Keybindings for the display window
            quit = "q",
            toggle_info = "<CR>",
            diff = "d",
            prompt_revert = "r",
        },
    },
    luarocks = {
        python_cmd = "python3", -- Set the python command to use for running hererocks
    },
    log = { level = "warn" }, -- The default print log level. One of: 'trace', 'debug', 'info', 'warn', 'error', 'fatal'.
    profile = {
        enable = false,
        threshold = 1, -- integer in milliseconds, plugins which load faster than this won't be shown in profile output
    },
}

-- if fn.filereadable(packer.config.compile_path) ~= 1 then
--   error('Packer compile path is not readable install_path: ' .. install_path .. ' compile_path: ' .. packer.config.compile_path)
--   return
-- end

return packer.startup(function(use)
    -- use {'VonHeikemen/lsp-zero.nvim', requires = {}}
    -- use {'hrsh7th/nvim-cmp', requires = 'neovim/nvim-lspconfig'}
    -- use {'hrsh7th/cmp-nvim-lsp', requires = {'neovim/nvim-lspconfig', 'hrsh7th/nvim-cmp'}}
    -- use {'hrsh7th/cmp-nvim-lua', requires = {'neovim/nvim-lspconfig', 'hrsh7th/nvim-cmp'}}
    -- use {'hrsh7th/cmp-buffer', requires = {'neovim/nvim-lspconfig', 'hrsh7th/nvim-cmp'}}
    -- use {'hrsh7th/cmp-path', requires = {'neovim/nvim-lspconfig', 'hrsh7th/nvim-cmp'}}
    -- use {'hrsh7th/cmp-cmdline', requires = {'neovim/nvim-lspconfig', 'hrsh7th/nvim-cmp'}}
    -- use {'tzachar/cmp-tabnine', run='./install.sh', requires = 'hrsh7th/nvim-cmp'}

    use { "ms-jpq/coq_nvim", branch = "coq" }
    use { "ms-jpq/coq.artifacts", branch = "artifacts", requires = "ms-jpq/coq_nvim" }
    use { "ms-jpq/coq.thirdparty", branch = "3p", requires = "ms-jpq/coq_nvim" }
    -- use {'LumaKernel/ddc-file', requires = 'Shougo/ddc.vim'}
    -- use {'LumaKernel/ddc-tabnine', requires = 'Shougo/ddc.vim'}
    -- use {'Shougo/ddc-around', requires = 'Shougo/ddc.vim'}
    -- use {'Shougo/ddc-converter_remove_overlap', requires = 'Shougo/ddc.vim'}
    -- use {'Shougo/ddc-matcher_head', requires = 'Shougo/ddc.vim'}
    -- use {'Shougo/ddc-nvim-lsp', requires = {'Shougo/ddc.vim', 'neovim/nvim-lspconfig'}}
    -- use {'Shougo/ddc-sorter_rank', requires = 'Shougo/ddc.vim'}
    -- use {'Shougo/ddc.vim', requires = 'vim-denops/denops.vim'}
    -- use {'Shougo/deoppet.nvim'}
    use { "Shougo/pum.vim" }
    use { "terrortylor/nvim-comment" }
    use { "SmiteshP/nvim-navic", requires = { "neovim/nvim-lspconfig", "nvim-treesitter/nvim-treesitter" } }
    use { "editorconfig/editorconfig-vim" }
    use { "lambdalisue/gin.vim" }
    use { "lewis6991/gitsigns.nvim" }
    -- use {'matsui54/denops-popup-preview.vim', requires = {'vim-denops/denops.vim', 'Shougo/pum.vim', 'Shougo/ddc-nvim-lsp'}, run = ':call popup_preview#enable()'}
    -- use {'matsui54/denops-signature_help', requires = {'vim-denops/denops.vim', 'Shougo/pum.vim', 'Shougo/ddc-nvim-lsp'}, run = ':call signature_help#enable()'}
    use { "nathom/filetype.nvim" }
    use { "navarasu/onedark.nvim", requires = "nvim-treesitter/nvim-treesitter" }
    use { "neovim/nvim-lspconfig" }
    use { "ray-x/lsp_signature.nvim", requires = "neovim/nvim-lspconfig" }

    use { "nvim-treesitter/nvim-treesitter", run = ":TSUpdate" }
    -- use {'tani/ddc-fuzzy', requires = 'Shougo/ddc.vim'}
    -- use {'vim-denops/denops.vim', branch = 'main'}
    use { "wbthomason/packer.nvim", opt = true }
    use { "williamboman/mason-lspconfig.nvim", requires = { "neovim/nvim-lspconfig", "williamboman/mason.nvim" } }
    use { "williamboman/mason.nvim", requires = "neovim/nvim-lspconfig" }
    use { "gpanders/editorconfig.nvim" }
    use {
        "norcalli/nvim-colorizer.lua",
        config = function()
            require("colorizer").setup()
        end,
    }
    use { "nvim-lua/plenary.nvim" }
    use { "nvim-telescope/telescope.nvim", branch = "master", requires = "nvim-lua/plenary.nvim" }
    use {
        "nvim-telescope/telescope-file-browser.nvim",
        requires = { "nvim-telesope/telescope.nvim", "nvim-lua/plenary.nvim" },
    }
    use { "glepnir/lspsaga.nvim", branch = "main", requires = "neovim/nvim-lspconfig" }
    use { "nvimtools/null-ls.nvim", branch = "main" }
    use { "kyazdani42/nvim-web-devicons" }
    use { "akinsho/bufferline.nvim", tag = "v2.*", requires = "kyazdani42/nvim-web-devicons" }
    use { "nvim-lualine/lualine.nvim", requires = { "kyazdani42/nvim-web-devicons", opt = true } }

    require "plugins.packer"
    if packer_bootstrap then
        packer.sync()
    end

    require "plugins.navic"
    require "plugins.telescope"
    require "plugins.treesitter"
    require "plugins.bufferline"
    require "plugins.comment"
    require "plugins.mason"
    -- require('plugins.cmp')
    -- require('plugins.ddc')
    -- require('plugins.deoppet')
    require "plugins.filetype"
    require "plugins.gitsigns"
    -- require('plugins.lspsaga')
    require "plugins.lualine"
    require "plugins.onedark"
    require "plugins.null-ls"
end)
