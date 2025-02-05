-----------------------------------------------------------
-- Neovim Full Configuration (init.lua)
--
-- この設定ファイルは以下を実現します：
-- - lazy.nvim によるプラグイン管理（自動ブートストラップ）
-- - lsp-zero.nvim による LSP の設定（ホストに既にインストール済みのサーバーを利用）
--   ※ Nim 用の nimlsp はカスタム設定を追加
-- - nvim-cmp の管理は lsp-zero に任せる（manage_nvim_cmp = true）
-- - none-ls (nvimtools/none-ls.nvim) によるフォーマッター／リンターの設定
-- - nvim-dap / nvim-dap-ui によるデバッガー環境
-- - GitHub Copilot (copilot.lua) の統合
-- - EditorConfig の連携
-- - nvim-treesitter によるシンタックスハイライト・インデント
-- - lualine によるステータスライン
-- - 効率的な開発を支援する補助プラグイン：
--   which-key, Telescope, gitsigns, Comment.nvim (Ctrl+C によるコメント切替),
--   indent-blankline (v3仕様), nvim-autopairs, persisted.nvim
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
  -- ※ lazy を無効にして確実にロード
  ------------------------------------------------------------------
  {
    "yetone/avante.nvim",
    lazy = false,
    config = function()
      local avante = safe_require("avante")
      if avante then
        avante.setup({ theme = "default" })
      end
    end,
  },

  ------------------------------------------------------------------
  -- Plugin: lsp-zero.nvim (LSP の設定)
  -- ※ ホストに既にインストール済みの LSP サーバー（clangd, gopls, rust_analyzer, zls, pyright）
  --     およびカスタム設定の nimlsp を利用
  ------------------------------------------------------------------
  {
    "VonHeikemen/lsp-zero.nvim",
    branch = "v4.x",
    lazy = false,
    config = function()
      local lsp = safe_require("lsp-zero")
      if not lsp then return end

      -- lsp-zero のプリセット設定。manage_nvim_cmp を true にして nvim-cmp の管理を任せる
      lsp.preset({
        float_border = "rounded",
        set_lsp_keymaps = true,
        manage_nvim_cmp = true,
        suggest_lsp_servers = false,
      })

      -- ※ lsp-zero は default_keymaps を自動設定するので、on_attach の個別設定は不要です

      -- カスタム設定：nimlsp を明示的に設定（ホストにインストール済みである前提）
      local lspconfig = safe_require("lspconfig")
      if lspconfig then
        lspconfig.nimlsp = lspconfig.nimlsp or {}
        lspconfig.nimlsp.setup({
          cmd = { os.getenv("NIMLSP_PATH") or "nimlsp" },
          filetypes = { "nim" },
          root_dir = lspconfig.util.root_pattern("nim.cfg", ".git"),
          on_attach = function(client, bufnr)
            lsp.default_keymaps({ buffer = bufnr })
          end,
          capabilities = lsp.capabilities,
        })
      end

      local lsputil = safe_require("lspconfig.util")

      if lsputil then
      -- 各言語サーバーごとに、環境変数でバイナリのパスを指定する設定例
      lsp.configure("clangd", {
        cmd = { "/usr/bin/clangd", "--background-index" },
        filetypes = { "c", "cpp", "objc", "objcpp" },
        root_dir = lsputil.root_pattern("compile_commands.json", "compile_flags.txt", ".git"),
      })

      lsp.configure("gopls", {
        cmd = { os.getenv("GOPATH").."/bin/gopls" or "gopls" },
        filetypes = { "go", "gomod" },
        root_dir = lsputil.root_pattern("go.work", "go.mod", ".git"),
      })

      lsp.configure("rust_analyzer", {
        cmd = { os.getenv("CARGO_HOME").."/bin/rust-analyzer" or "rust-analyzer" },
        filetypes = { "rust" },
        settings = {
          ["rust-analyzer"] = {
            cargo = { allFeatures = true },
            checkOnSave = { command = "clippy" },
          },
        },
        root_dir = lsputil.root_pattern("Cargo.toml", "rust-project.json", ".git"),
      })

      lsp.configure("zls", {
        cmd = { os.getenv("ZLS_PATH") or "zls" },
        filetypes = { "zig" },
        root_dir = lsputil.root_pattern("build.zig", ".git"),
      })

      lsp.configure("pyright", {
        cmd = { os.getenv("PYRIGHT_PATH") or "pyright-langserver", "--stdio" },
        filetypes = { "python" },
        root_dir = lsputil.root_pattern("pyproject.toml", "setup.py", ".git"),
      })
      end

      lsp.setup()
    end,
  },

  ------------------------------------------------------------------
  -- Plugin: nvim-cmp 関連プラグイン
  -- lsp-zero による管理に任せるため、個別の設定は行わずプラグインとして登録
  ------------------------------------------------------------------
  { "hrsh7th/nvim-cmp" },
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
    lazy = false,
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
      -- 例: C/C++ 用のデバッガー (cppdbg) ※ 各自パスを調整してください
      dap.adapters.cppdbg = {
        id = "cppdbg",
        type = "executable",
        command = os.getenv("CPPDBG_PATH") or "path/to/cpptools/extension/debugAdapters/bin/OpenDebugAD7",
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
        command = os.getenv("PYTHON_DEBUG_PATH") or "python",
        args = { "-m", "debugpy.adapter" },
      }
      dap.configurations.python = {
        {
          type = "python",
          request = "launch",
          name = "Launch file",
          program = "${file}",
          pythonPath = function() return os.getenv("PYTHON") or "python" end,
        },
      }
    end,
  },
  {
    "rcarriga/nvim-dap-ui",
    lazy = false,
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
  -- Plugin: nvim-treesitter (シンタックスハイライト・インデント)
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
    dependencies = { "nvim-tree/nvim-web-devicons" },
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

  -- which-key: キーバインドヘルプ表示
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

  -- telescope: ファジーファインダー（ファイル検索、ライブグレップ等）
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

  -- gitsigns: Git 差分表示
  {
    "lewis6991/gitsigns.nvim",
    event = "BufRead",
    config = function()
      local gitsigns = safe_require("gitsigns")
      if gitsigns then
        gitsigns.setup({
          signs = {
            add = function() return { text = "│" } end,
            change = function() return { text = "│" } end,
            delete = function() return { text = "_" } end,
            topdelete = function() return { text = "‾" } end,
            changedelete = function() return { text = "~" } end,
          },
        })
      end
    end,
  },

  -- Comment.nvim: Ctrl+C でコメント切替
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

  -- indent-blankline: インデントガイド表示 (v3仕様)
  {
    "lukas-reineke/indent-blankline.nvim",
    event = "BufRead",
    config = function()
      local ibl = safe_require("indent_blankline")
      if ibl then
        ibl.setup({
          char = "│",
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
