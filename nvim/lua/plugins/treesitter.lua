local status, treesitter = pcall(require, 'nvim-treesitter.configs')
if (not status) then
  error("treesitter config is not installed")
  return
end

treesitter.setup {
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
    "yaml"
    "zig",
  },
  autotag = {
    enable = true,
  },
}

local status, parser = pcall(require, 'nvim-treesitter.parsers')
if (not status) then
  error("treesitter parser is not installed")
  return
end

parser.get_parser_configs().tsx.filetype_to_parsername = { "javascript", "typescript.tsx" }
