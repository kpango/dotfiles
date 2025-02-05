-----------------------------------------------------------
-- Neovim Full Configuration (init.lua)
--
-- この設定ファイルは以下を実現します：
-- - lazy.nvim によるプラグイン管理（自動ブートストラップ）
-- - nvim-lspconfig による LSP (ホストにすでにインストール済みのサーバーを利用)
-- - nvim-cmp + LuaSnip による自動補完
-- - none-ls (nvimtools/none-ls.nvim) によるフォーマッター／リンターの設定
-- - nvim-dap / nvim-dap-ui によるデバッガー環境
-- - GitHub Copilot (copilot.lua) の統合
-- - EditorConfig の連携
-- - nvim-treesitter によるシンタックスハイライト・インデント
-- - lualine によるステータスライン
-- - 効率的な開発を支援する補助プラグイン:
--   which-key, Telescope, gitsigns, Comment.nvim (Ctrl+C でコメント切替),
--   indent-blankline, nvim-autopairs, persisted.nvim
-----------------------------------------------------------

-- 1. lazy.nvim の自動ブートストラップ
local fn = vim.fn
local install_path = fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(install_path) then
  fn.system({
    "git",
    "clone",
    "--depth", "1",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    install_path,
  })
end
vim.opt.rtp:prepend(install_path)

-- 2. グローバルオプションの設定
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.updatetime = 300
vim.opt.lazyredraw = true
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "preview" }
vim.opt.shortmess:append("c")

-- 3. 安全なモジュール読み込み用関数
local function safe_require(module_name)
  local status, module = pcall(require, module_name)
  if not status then
    vim.notify("Error loading module: " .. module_name, vim.log.levels.ERROR)
    return nil
  end
  return module
end

-----------------------------------------------------------
-- 4. lazy.nvim を用いたプラグイン設定
-----------------------------------------------------------
require("lazy").setup({

  ------------------------------------------------------------------
  -- Plugin: Avante.nvim
  ------------------------------------------------------------------
  {
    "yetone/avante.nvim",
    config = function()
      local avante = safe_require("avante")
      if avante then
        avante.setup({ theme = "default" })
      end
    end,
  },

  ------------------------------------------------------------------
  -- Plugin: nvim-lspconfig (LSP: ホストにインストール済みのサーバーを利用)
  ------------------------------------------------------------------
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = safe_require("lspconfig")
      if not lspconfig then return end

      -- 共通 on_attach 関数: 各バッファに LSP 関連キーマッピングを設定
      local on_attach = function(client, bufnr)
        local opts = { noremap = true, silent = true, buffer = bufnr }
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "<leader>f", function() vim.lsp.buf.format({ async = true }) end, opts)
      end

      local capabilities = vim.lsp.protocol.make_client_capabilities()
      local cmp_nvim_lsp = safe_require("cmp_nvim_lsp")
      if cmp_nvim_lsp then
        capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
      end

      -- ホストに既にインストールされている LSP サーバーを利用
      local servers = { "clangd", "gopls", "rust_analyzer", "zls", "nimlsp", "pyright" }
      for _, server in ipairs(servers) do
        lspconfig[server].setup({
          on_attach = on_attach,
          capabilities = capabilities,
        })
      end
    end,
  },

  ------------------------------------------------------------------
  -- Plugin: nvim-cmp (自動補完)
  ------------------------------------------------------------------
  {
    "hrsh7th/nvim-cmp",
    config = function()
      local cmp = safe_require("cmp")
      if not cmp then return end
      cmp.setup({
        snippet = {
          expand = function(args)
            safe_require("luasnip").lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
        }, {
          { name = "buffer" },
        }),
      })
    end,
  },
  { "hrsh7th/cmp-nvim-lsp" },
  { "hrsh7th/cmp-buffer" },
  { "hrsh7th/cmp-path" },
  { "hrsh7th/cmp-cmdline" },
  { "L3MON4D3/LuaSnip" },
  { "saadparwaiz1/cmp_luasnip" },

  ------------------------------------------------------------------
  -- Plugin: none-ls (フォーマッター／リンター)
  -- 参考: https://github.com/nvimtools/none-ls.nvim
  ------------------------------------------------------------------
  {
    "nvimtools/none-ls.nvim",
    config = function()
      local none_ls = safe_require("none-ls")
      if not none_ls then return end
      none_ls.setup({
        sources = {
          none_ls.builtins.formatting.clang_format,
          none_ls.builtins.formatting.gofmt,
          none_ls.builtins.formatting.rustfmt,
          none_ls.builtins.formatting.zigfmt,
          none_ls.builtins.formatting.nimpretty,
          none_ls.builtins.formatting.black,
          none_ls.builtins.diagnostics.flake8,
        },
      })
    end,
  },

  ------------------------------------------------------------------
  -- Plugin: nvim-dap (デバッガー) と nvim-dap-ui
  ------------------------------------------------------------------
  {
    "mfussenegger/nvim-dap",
    config = function()
      local dap = safe_require("dap")
      if not dap then return end
      -- 例: C/C++ 用のデバッガー (cppdbg) ※各自パスを調整してください
      dap.adapters.cppdbg = {
        id = "cppdbg",
        type = "executable",
        command = "path/to/cpptools/extension/debugAdapters/bin/OpenDebugAD7",
      }
      dap.configurations.cpp = {
        {
          name = "Launch file",
          type = "cppdbg",
          request = "launch",
          program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopAtEntry = true,
        },
      }
      -- Python 用の例 (debugpy)
      dap.adapters.python = {
        type = "executable",
        command = "python",
        args = { "-m", "debugpy.adapter" },
      }
      dap.configurations.python = {
        {
          type = "python",
          request = "launch",
          name = "Launch file",
          program = "${file}",
          pythonPath = function() return "python" end,
        },
      }
    end,
  },
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap" },
    config = function()
      local dap = safe_require("dap")
      local dapui = safe_require("dapui")
      if not (dap and dapui) then return end
      dapui.setup()
      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end
    end,
  },

  ------------------------------------------------------------------
  -- Plugin: GitHub Copilot の統合 (copilot.lua)
  ------------------------------------------------------------------
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function()
      local copilot = safe_require("copilot")
      if copilot then
        copilot.setup({
          panel = { enabled = true },
          suggestion = { enabled = true },
        })
      end
    end,
  },

  ------------------------------------------------------------------
  -- Plugin: EditorConfig (エディタ設定の統一)
  ------------------------------------------------------------------
  {
    "editorconfig/editorconfig-vim",
    lazy = false,
  },

  ------------------------------------------------------------------
  -- Plugin: nvim-treesitter (シンタックスハイライト等)
  ------------------------------------------------------------------
  {
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
    event = "BufReadPost",
    config = function()
      local ts_configs = safe_require("nvim-treesitter.configs")
      if ts_configs then
        ts_configs.setup({
          auto_install = true,
          highlight = { enable = true },
          indent = { enable = true },
          ensure_installed = { "bash", "c", "cpp", "go", "lua", "rust", "zig", "nim", "python" },
        })
      end
    end,
  },

  ------------------------------------------------------------------
  -- Plugin: lualine (ステータスライン)
  ------------------------------------------------------------------
  {
    "nvim-lualine/lualine.nvim",
    event = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" }, -- devicons は Telescope などでも利用
    config = function()
      local lualine = safe_require("lualine")
      if lualine then
        lualine.setup({
          options = {
            theme = "auto",
            section_separators = "",
            component_separators = "|",
          },
        })
      end
    end,
  },

  ------------------------------------------------------------------
  -- 以下、効率的な開発を支援する追加プラグイン
  ------------------------------------------------------------------

  -- which-key: キーバインドのヘルプ表示
  {
    "folke/which-key.nvim",
    config = function()
      local wk = safe_require("which-key")
      if wk then
        wk.setup({
          plugins = { spelling = true },
          window = { border = "single" },
        })
      end
    end,
    event = "VeryLazy",
  },

  -- telescope: ファジーファインダー (ファイル検索、ライブグレップ等)
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local telescope = safe_require("telescope")
      if telescope then
        telescope.setup({
          defaults = {
            prompt_prefix = " ",
            selection_caret = " ",
          },
        })
      end
    end,
    cmd = "Telescope",
  },

  -- gitsigns: Git の差分表示
  {
    "lewis6991/gitsigns.nvim",
    event = "BufRead",
    config = function()
      local gitsigns = safe_require("gitsigns")
      if gitsigns then
        gitsigns.setup({
          signs = {
            add = { text = "│" },
            change = { text = "│" },
            delete = { text = "_" },
            topdelete = { text = "‾" },
            changedelete = { text = "~" },
          },
        })
      end
    end,
  },

  -- Comment.nvim: コメントの切り替え (Ctrl+C で操作)
  {
    "numToStr/Comment.nvim",
    config = function()
      local comment = safe_require("Comment")
      if comment then
        comment.setup()
        local api = safe_require("Comment.api")
        if api then
          vim.keymap.set("n", "<C-c>", api.toggle.linewise.current, { desc = "Toggle comment" })
          vim.keymap.set("v", "<C-c>", api.toggle.linewise, { desc = "Toggle comment" })
        end
      end
    end,
    keys = { "<C-c>" },
  },

  -- indent-blankline: インデントガイド表示
  {
    "lukas-reineke/indent-blankline.nvim",
    event = "BufRead",
    config = function()
      local ibl = safe_require("indent_blankline")
      if ibl then
        ibl.setup({
          char = "│",
          show_trailing_blankline_indent = false,
        })
      end
    end,
  },

  -- nvim-autopairs: 自動括弧補完
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      local npairs = safe_require("nvim-autopairs")
      if npairs then
        npairs.setup({})
      end
    end,
  },

  -- persisted.nvim: セッション管理
  {
    "olimorris/persisted.nvim",
    config = function()
      local persisted = safe_require("persisted")
      if persisted then
        persisted.setup({
          use_git_branch = true,
        })
      end
    end,
    cmd = { "SessionSave", "SessionLoad" },
  },

}, {
  root = fn.stdpath("config") .. "/lazy",  -- プラグイン配置ディレクトリ
})

-----------------------------------------------------------
-- 5. グローバルキーマッピング
-----------------------------------------------------------
-- DAP 用のキーマッピング
vim.keymap.set("n", "<F5>", function() safe_require("dap").continue() end, { silent = true })
vim.keymap.set("n", "<F10>", function() safe_require("dap").step_over() end, { silent = true })
vim.keymap.set("n", "<F11>", function() safe_require("dap").step_into() end, { silent = true })
vim.keymap.set("n", "<F12>", function() safe_require("dap").step_out() end, { silent = true })

-- Telescope を用いたファジー検索のキーマッピング
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { silent = true, noremap = true })

-----------------------------------------------------------
-- End of configuration
-----------------------------------------------------------
