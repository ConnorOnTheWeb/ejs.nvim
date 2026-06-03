local M = {}

M.defaults = {
  -- Register the embedded_template Tree-sitter parser for .ejs files
  -- and enable syntax highlighting via injections.
  treesitter = true,

  -- Attach html-lsp and ts_ls to EJS buffers via FileType autocommand.
  lsp = true,

  -- Load LuaSnip snippets for common EJS patterns (if LuaSnip is installed).
  snippets = true,
}

return M
