local fn = vim.fn
local pkg_path = fn.stdpath("config") .. "/lazy"
local lazypath = pkg_path .. "/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/folke/lazy.nvim",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local status, lazy = pcall(require, 'lazy')
if (not status) then
  error('lazy is not installed install_path: ' .. install_path..' packpath: '..vim.o.packpath)
  return
end

lazy.setup({
--    {'ms-jpq/coq_nvim',
--        branch = 'coq',
--	build = ":COQdeps",
--	lazy = true,
--	init = function()
--	    vim.g.coq_settings = {
--	        auto_start = 'shut-up',
--    	        xdg = true,
--    	        match = {max_results = 100},
--    	        keymap = {jump_to_mark = "<c-cr>"},
--    	        display = {icons = {mode = 'long'}, preview = {resolve_timeout = 5}},
--    	        clients = {
--		  third_party = {enabled = true},
--		  tabnine = {enabled = true},
--		},
--    	        limits = {
--    	            completion_auto_timeout = 2,
--    	            completion_manual_timeout = 5
--    	        }
--    	    }
--	end,
--	dependencies = {
--	    {'ms-jpq/coq.artifacts', branch = 'artifacts'},
--	    {'ms-jpq/coq.thirdparty',
--	        branch = '3p',
--		config = function()
--                    local status, c3p = pcall(require, 'coq_3p')
--                    if (not status) then
--                      error('coq_3p is not installed install_path: ' .. install_path..' packpath: '..vim.o.packpath)
--                      return
--                    end
--		    c3p({
--		      {src = "nvimlua", short_name = "NVIM", conf_only = true},
--		      {src = "copilot", short_name = "COP", accept_key = "<c-f>"},
--		    })
--		end,
--	    },
--	},
--    },
    {"hrsh7th/nvim-cmp",
        opts = function()
	    local status, cmp = pcall(require, 'cmp')
            if (not status) then
                error('cmp is not installed install_path: ' .. install_path..' packpath: '..vim.o.packpath)
                return
            end
	    return {
                snippet = {
                      expand = function(args)
                          vim.fn["vsnip#anonymous"](args.body)
                      end,
                },
                sources = {
                    { name = "nvim_lsp" },--ソース類を設定
                    { name = 'vsnip' }, -- For vsnip users.
                    { name = "buffer" },
                    { name = "path" },
                },
                mapping = cmp.mapping.preset.insert({
                    ["<C-p>"] = cmp.mapping.select_prev_item(), --Ctrl+pで補完欄を一つ上に移動
                    ["<C-n>"] = cmp.mapping.select_next_item(), --Ctrl+nで補完欄を一つ下に移動
                    ['<C-l>'] = cmp.mapping.complete(),
                    ['<C-e>'] = cmp.mapping.abort(),
                    ["<C-y>"] = cmp.mapping.confirm({ select = true }),--Ctrl+yで補完を選択確定
                }),
                experimental = {
                    ghost_text = false,
                },
                -- Lspkind(アイコン)を設定
                formatting = {
                    -- format = lspkind.cmp_format({
                    --     mode = 'symbol', -- show only symbol annotations
                    --     maxwidth = 50, -- prevent the popup from showing more than provided characters (e.g 50 will not show more than 50 characters)
                    --     ellipsis_char = '...', -- when popup menu exceed maxwidth, the truncated part would show ellipsis_char instead (must define maxwidth first)
                    --     -- The function below will be called before any actual modifications from lspkind
                    --     -- so that you can provide more controls on popup customization. (See [#30](https://github.com/onsails/lspkind-nvim/pull/30))
                    -- })
                },
            }
        end,
        dependencies = {
	    "hrsh7th/cmp-nvim-lsp",
	    "hrsh7th/vim-vsnip",
        },
    },
    {'numToStr/Comment.nvim',
        config=true,
        lazy=true,
        keys={
            {'<C-_>', ":lua require('Comment.api').toggle.linewise.current()<CR>", {noremap = true, silent = true}, desc="", mode='n'},
            {'<C-_>', '<ESC><CMD>lua require("Comment.api").toggle.linewise(vim.fn.visualmode())<CR>', {noremap = true, silent = true}, desc="", mode='x'},
            {'<C-_>', ":lua require('Comment.api').toggle.linewise.current() <CR>", {noremap = true, silent = true}, desc="", mode='i'},
        },
    },
    {'neovim/nvim-lspconfig',
        lazy=true,
        keys={
            {'gD', vim.lsp.buf.declaration, {noremap = true, silent = true}, desc="Go To Declaration", mode='n'},
            {'gi', vim.lsp.buf.implementation, {noremap = true, silent = true}, desc="Go To Implementation", mode='n'},
            {"K", vim.lsp.buf.hover, {silent = true}, desc="Show Info", mode="n"},
            {"<leader>k", vim.lsp.buf.signature_help, {silent = true, noremap = true}, desc="Show Signature", mode="n"},
            {'<Leader>gr', vim.lsp.buf.references, {noremap = true, silent = true}, desc="Go To References", mode='n'},
            {'<Leader>D', vim.lsp.buf.type_definition, {noremap = true, silent = true}, desc="Show Type Definition", mode='n'},
        },
    },
    {'nvim-treesitter/nvim-treesitter',
        build = ':TSUpdate',
        dependencies = 'nvim-treesitter/nvim-treesitter-textobjects',
    },
    {'williamboman/mason.nvim',
        config = true,
	dependencies = 'neovim/nvim-lspconfig',
    },
    {'williamboman/mason-lspconfig.nvim',
        opts = {
            ensure_installed = {
                'gopls',
		'sumneko_lua',
            },
            automatic_installation = true,
	},
        config = function()
            local status, lspconfig = pcall(require, 'lspconfig')
            if (not status) then
              error('lspconfig is not installed install_path: ' .. install_path..' packpath: '..vim.o.packpath)
              return
            end
            -- local status, coq = pcall(require, 'coq')
            -- if (not status) then
            --   error('coq is not installed install_path: ' .. install_path..' packpath: '..vim.o.packpath)
            --   return
            -- end
	    local status, cmplsp = pcall(require, 'cmp_nvim_lsp')
            if (not status) then
              error('cmp_nvim_lsp is not installed install_path: ' .. install_path..' packpath: '..vim.o.packpath)
              return
            end

            local status, mason_lspconfig = pcall(require, 'mason-lspconfig')
            if (not status) then
              error('mason_lspconfig is not installed install_path: ' .. install_path..' packpath: '..vim.o.packpath)
              return
            end

            local capabilities = cmplsp.default_capabilities()
            mason_lspconfig.setup_handlers {
              function (server_name)
                local opts = {}
                if server_name == "sumneko_lua" then
                  opts.settings = {
                    Lua = {
                      diagnostics = { globals = { 'vim' } },
                    }
                  }
                elseif server_name == "gopls" then
                  opts = {
            	cmd = {"gopls", "--remote=auto"},
            	filetypes = {"go", "gomod"},
            	root_dir = lspconfig.util.root_pattern(".git", "go.mod", "go.sum"),
                  }
                end
                opts.capabilities = capabilities
                lspconfig[server_name].setup(opts)
              end,
            }
	end,
        dependencies = 'williamboman/mason.nvim',
    },
    {'gpanders/editorconfig.nvim'},
    {"glepnir/lspsaga.nvim",
        lazy=true,
        keys={
            {"<leader>ca", "<cmd><C-U>Lspsaga range_code_action<CR>", {silent = true, noremap = true}, desc="Range Code Action", mode="v"},
            {"<leader>ca", "<cmd>Lspsaga code_action<CR>", {silent = true, noremap = true}, desc="Code Action", mode="n"},
            {"<leader>e", "<cmd>Lspsaga show_line_diagnostics<CR>", {silent = true, noremap = true}, desc="Show Line Diagnostics", mode="n"},
            {'<Leader>[', "<cmd>Lspsaga diagnostic_jump_prev<CR>", {noremap = true, silent = true}, desc="Jump To The Next Diagnostics", mode='n'},
            {'<Leader>]', "<cmd>Lspsaga diagnostic_jump_next<CR>", {noremap = true, silent = true}, desc="Jump To The Previous Diagnostics", mode='n'},
            {"<Leader>T", "<cmd>Lspsaga open_floaterm<CR>", {silent = true}, desc="Open Float Term", mode="n"},
            {"<Leader>T", [[<C-\><C-n><cmd>Lspsaga close_floaterm<CR>]], {silent = true}, desc="Close Float Term", mode="t"},
            {"gr", "<cmd>Lspsaga rename<CR>", {silent = true, noremap = true}, desc="Rename", mode="n"},
            {"gh", "<cmd>Lspsaga lsp_finder<CR>", {silent = true, noremap = true}, desc="LSP Finder", mode="n"},
            {"gd", "<cmd>Lspsaga peek_definition<CR>", {silent = true}, desc="Peek Definition", mode="n"},
        },
        branch = "main",
        opts = {border_style = "rounded"},
        dependencies='neovim/nvim-lspconfig'
    },
    {'jose-elias-alvarez/null-ls.nvim',
        branch = 'main',
	dependencies = 'nvim-lua/plenary.nvim',
	config = true,
	opts = function()
	    local status, null_ls = pcall(require, 'null-ls')
            if (not status) then
              error('null-ls is not installed install_path: ' .. install_path..' packpath: '..vim.o.packpath)
              return
            end

	    return {
                sources = {
                    null_ls.builtins.diagnostics.cspell.with({
			 diagnostics_postprocess = function(diagnostic)
                      	     diagnostic.severity = vim.diagnostic.severity["WARN"]
                      	 end,
                      	 condition = function()
                      	     return vim.fn.executable('cspell') > 0
                      	 end
                    })
                },
	    }
       end,
    },
    {'nvim-tree/nvim-web-devicons'},
    {'akinsho/bufferline.nvim', version = "*", dependencies = 'nvim-tree/nvim-web-devicons', config = true},
    {'nvim-lualine/lualine.nvim',
        opts = {
            options = {
                icons_enabled = true,
                theme = 'gruvbox-material',
                component_separators = {left = '|', right = '|'},
                section_separators = {left = '', right = ''},
                disabled_filetypes = {"NvimTree", "packer", "TelescopePrompt"},
                always_divide_middle = true,
                globalstatuses = true,
                globalstatus = true,
                colored = false,
            },
            sections = {
                lualine_a = {'mode'},
                lualine_b = {
                    'branch', 'diff', {
                        'diagnostics',
                        sources = {'nvim_lsp', 'coc'},
                        update_in_insert = true,
                        always_visible = true
                    }
                },
                lualine_c = {
                   {
                      'filename',
                      path = 1,
                      file_status = true,
                      shorting_target = 40,
                      symbols = {
                          modified = '[+]',
                          readonly = '[RO]',
                          unnamed = 'Untitled',
                      }
                   }
                },
                lualine_x = {'filetype'},
		lualine_y = {
                   {'diagnostics', source = {'nvim-lsp'}},
                   {'progress'},
                   {'location'},
                },
                lualine_z = {''}
            },
            inactive_sections = {
                lualine_a = {},
                lualine_b = {},
                lualine_c = {{'filename', file_status = true, path = 1}},
                lualine_x = {'filetype'},
                lualine_y = {'%p%%', 'location'},
                lualine_z = {}
            },
            tabline = {},
            extensions = {"fugitive", "fzf", "nvim-tree"}
        },
	dependencies = 'nvim-tree/nvim-web-devicons',
    },
    {
	'mvllow/modes.nvim',
	config = true,
	opts = {
	  colors = {
	    copy = '#FFEE55',
	    delete = '#DC669B',
	    insert = '#55AAEE',
	    visual = '#DD5522',
          },
	},
    },
}, {
    root = pkg_path,
})
