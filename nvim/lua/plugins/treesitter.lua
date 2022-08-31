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
  ensure_installed = "all",
  -- ensure_installed = {
  --   "tsx",
  --   "toml",
  --   "fish",
  --   "php",
  --   "json",
  --   "yaml",
  --   "swift",
  --   "css",
  --   "html",
  --   "lua"
  -- },
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
