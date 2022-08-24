local fn = vim.fn
local install_path = fn.stdpath('data')..'/site/pack/packer/opt/packer.nvim'
print(install_path)
if fn.empty(fn.glob(install_path)) > 0 then
    packer_bootstrap = fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
    vim.api.nvim_command('packadd packer.nvim')
end

local status, packer = pcall(require, 'packer')
if (not status) then
  print("Packer is not installed")
  return
end

vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerCompile
  augroup end
]])

packer.init({
  ensure_dependencies   = true, -- Should packer install plugin dependencies?
  snapshot = nil, -- Name of the snapshot you would like to load at startup
  snapshot_path = join_paths(stdpath 'cache', 'packer.nvim'), -- Default save directory for snapshots
  package_root   = util.join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
  compile_path = util.join_paths(vim.fn.stdpath('config'), 'plugin', 'packer_compiled.lua'),
  plugin_package = 'packer', -- The default package for plugins
  max_jobs = nil, -- Limit the number of simultaneous jobs. nil means no limit
  auto_clean = true, -- During sync(), remove unused plugins
  compile_on_sync = true, -- During sync(), run packer.compile()
  disable_commands = false, -- Disable creating commands
  opt_default = false, -- Default to using opt (as opposed to start) plugins
  transitive_opt = true, -- Make dependencies of opt plugins also opt by default
  transitive_disable = true, -- Automatically disable dependencies f disabled plugins
  auto_reload_compiled = true, -- Automatically reload the compiled file after creating it.
  git = {
    cmd = 'git', -- The base command for git operations
    subcommands = { -- Format strings for git subcommands
      update         = 'pull --ff-only --progress --rebase=false',
      install        = 'clone --depth %i --no-single-branch --progress',
      fetch          = 'fetch --depth 999999 --progress',
      checkout       = 'checkout %s --',
      update_branch  = 'merge --ff-only @{u}',
      current_branch = 'branch --show-current',
      diff           = 'log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD',
      diff_fmt       = '%%h %%s (%%cr)',
      get_rev        = 'rev-parse --short HEAD',
      get_msg        = 'log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1',
      submodules     = 'submodule update --init --recursive --progress'
    },
    depth = 1, -- Git clone depth
    clone_timeout = 60, -- Timeout, in seconds, for git clones
    default_url_format = 'https://github.com/%s' -- Lua format string used for "aaa/bbb" style plugins
  },
  display = {
    non_interactive = false, -- If true, disable display windows for all operations
    open_fn  = nil, -- An optional function to open a window for packer's display
    open_cmd = '65vnew \\[packer\\]', -- An optional command to open a window for packer's display
    working_sym = '⟳', -- The symbol for a plugin being installed/updated
    error_sym = '✗', -- The symbol for a plugin with an error in installation/updating
    done_sym = '✓', -- The symbol for a plugin which has completed installation/updating
    removed_sym = '-', -- The symbol for an unused plugin which was removed
    moved_sym = '→', -- The symbol for a plugin which was moved (e.g. from opt to start)
    header_sym = '━', -- The symbol for the header line in packer's display
    show_all_info = true, -- Should packer show all update details automatically?
    prompt_border = 'double', -- Border style of prompt popups.
    keybindings = { -- Keybindings for the display window
      quit = 'q',
      toggle_info = '<CR>',
      diff = 'd',
      prompt_revert = 'r',
    }
  },
  luarocks = {
    python_cmd = 'python3' -- Set the python command to use for running hererocks
  },
  log = { level = 'warn' }, -- The default print log level. One of: "trace", "debug", "info", "warn", "error", "fatal".
  profile = {
    enable = false,
    threshold = 1, -- integer in milliseconds, plugins which load faster than this won't be shown in profile output
  },
  autoremove = false, -- Remove disabled or unused plugins without prompting the user
})

return packer.startup(function(use)
    use {'wbthomason/packer.nvim', opt = true}
    use {'LumaKernel/ddc-file', requires = {'Shougo/ddc.vim'}}
    use {'LumaKernel/ddc-tabnine', requires = {'Shougo/ddc.vim'}}
    use {'Shougo/ddc.vim', requires = {'vim-denops/denops.vim'}}
    use {'Shougo/ddc-around', requires = {'Shougo/ddc.vim'}}
    use {'Shougo/ddc-matcher_head', requires = {'Shougo/ddc.vim'}}
    use {'Shougo/ddc-sorter_rank', requires = {'Shougo/ddc.vim'}}
    use {'Shougo/ddc-nvim-lsp', requires = {'Shougo/ddc.vim'}}
    use {'Shougo/ddc-converter_remove_overlap', requires = {'Shougo/ddc.vim'}}
    use {'Shougo/ddc-matcher_head', requires = {'Shougo/ddc.vim'}}
    use {'Shougo/ddc-sorter_rank', requires = {'Shougo/ddc.vim'}}
    use {'tani/ddc-fuzzy', requires = {'Shougo/ddc.vim'}}
    use {'Shougo/deoppet.nvim'}
    use {'Shougo/pum.vim'}
    use {'junegunn/fzf', run = ":call fzf#install()"}
    use {'junegunn/fzf.vim', requires = {'junegunn/fzf'}}
    use {'lewis6991/gitsigns.nvim'}
    use {'lambdalisue/gin.vim'}
    use {'editorconfig/editorconfig-vim'}
    use {'mattn/vim-goimports', ft = 'go'}
    use {'neovim/nvim-lspconfig'}
    use {'sbdchd/neoformat'}
    use {'tyru/caw.vim'}
    use {'vim-denops/denops.vim', branch = 'main'}
    use {'williamboman/mason-lspconfig.nvim'}
    use {'williamboman/mason.nvim'}
    use {'nathom/filetype.nvim', event = 'VimEnter'}
    use {'editorconfig/editorconfig-vim'}
    use { "SmiteshP/nvim-navic",
      requires = [
        "neovim/nvim-lspconfig",
        "nvim-treesitter/nvim-treesitter",
      ],
      module = "nvim-navic",
      config = function()
        require("nvim-navic").setup()
      end,
    }
    use {'nvim-lualine/lualine.nvim',
        requires = { 'kyazdani42/nvim-web-devicons', opt = true }
        event = "VimEnter",
        config = function()
          require("config.lualine").setup()
        end,
    }
    use {'nvim-treesitter/nvim-treesitter',
        run = ':TSUpdate'
        config = function()
           require("config.treesitter").setup()
        end,
    }
    use {'norcalli/nvim-colorizer.lua',
        event = "VimEnter",
        config = function()
           require("config.colorizer").setup()
        end,
    }
    use {'nvim-telescope/telescope.nvim', tag = '0.1.0', requires = {{'nvim-lua/plenary.nvim'}}}
    use {'akinsho/bufferline.nvim', tag = "v2.*", requires = 'kyazdani42/nvim-web-devicons'}
    use {"glepnir/lspsaga.nvim", branch = "main"}

    if packer_bootstrap then
      packer.sync()
    end
end,

config = {
  display = {
    open_fn = function()
      return require('packer.util').float({ border = 'single' })
    end
  }
  profile = {
    enable = true,
    threshold = 1 -- the amount in ms that a plugins load time must be over for it to be included in the profile
  }
})
