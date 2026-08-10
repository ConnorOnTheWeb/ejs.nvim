local M = {}

M.defaults = {
  -- Register the embedded_template Tree-sitter parser for .ejs files
  -- and enable syntax highlighting via injections.
  treesitter = true,

  -- Attach html-lsp and ts_ls to EJS buffers via FileType autocommand.
  lsp = true,

  -- Load LuaSnip snippets for common EJS patterns (if LuaSnip is installed).
  -- Independent of the completion source below, which offers the same
  -- scaffolds to any completion engine without needing a snippet plugin.
  snippets = true,

  -- Completion. One engine-agnostic core (lua/ejs/completion.lua) feeds every
  -- adapter: EJS tag delimiters, block scaffolds, and `include()` path
  -- completion. Each adapter is skipped silently when its engine is absent.
  completion = {
    -- Register the `ejs` source with nvim-cmp.
    cmp = true,

    -- Register the `ejs` source with blink.cmp. Requires blink.cmp >= v1.6
    -- for its runtime registration API; older versions need the manual
    -- `sources.providers` entry documented in the README.
    blink = true,

    -- Set up a complete-function for engines with no source API of their own
    -- (Neovim 0.12's built-in completion, mini.completion, coq_nvim).
    omni = false,

    -- Insert the expanded form rather than the bare label: accepting `<%=`
    -- inserts `<%= | %>`, and `ejsif` inserts a full if/else block.
    snippets = true,
  },

  -- Warn about `include()` paths that do not resolve to a file, and about
  -- `<%# %>` comments that end earlier than they appear to.
  diagnostics = true,

  -- Fold `<% if (...) { %> ... <% } %>` control-flow blocks. Folds start
  -- open (foldlevel 99).
  folding = true,

  -- Documentation for the EJS delimiter under the cursor, on `K` — what
  -- separates `<%=` from `<%-`, and `%>` from `-%>` and `_%>`. The mapping
  -- falls through to `vim.lsp.buf.hover()` (html-lsp / ts_ls are attached to
  -- EJS buffers) whenever the cursor is not on a delimiter.
  hover = true,
}

return M
