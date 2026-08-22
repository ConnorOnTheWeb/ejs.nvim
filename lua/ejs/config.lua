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
  --
  -- The two checks are separate because they are wrong in unrelated ways.
  -- `missing_include` depends on paths resolving the way the EJS runtime
  -- resolves them, which a custom `root` option or a build step can break.
  -- `broken_comment` reports a genuine parser limitation and is the less
  -- likely of the two to want silencing.
  --
  -- Each takes 'error', 'warn', 'info', 'hint' or 'off'. `hint` is the useful
  -- one: it leaves the underline in the buffer while keeping the entry out of
  -- the location list. `diagnostics = false` (the pre-1.2.0 spelling) still
  -- turns both off.
  --
  -- The JavaScript syntax check the extension also performs is deliberately
  -- not ported, so there is no setting for it: `ts_ls` is already attached to
  -- `<% %>` regions by lua/ejs/lsp.lua and reports real syntax errors there
  -- with better positions than a joined-program heuristic can.
  diagnostics = {
    missing_include = 'warn',
    broken_comment = 'warn',
  },

  -- Override `gc` / `gcc` in EJS buffers so each line is commented in the
  -- style its own shape calls for. `commentstring` is a single string and an
  -- EJS template is made of five distinguishable line shapes, only one of
  -- which takes `<%# … %>` — see lua/ejs/comment.lua for the table and for
  -- what the flat comment string does to the other four.
  --
  -- Set false to leave `gc` alone; `commentstring` is still set to the dead
  -- branch either way, which is the safer static fallback.
  comment = true,

  -- Fold `<% if (...) { %> ... <% } %>` control-flow blocks. Folds start
  -- open (foldlevel 99).
  folding = true,

  -- Documentation for the EJS delimiter under the cursor, on `K` — what
  -- separates `<%=` from `<%-`, and `%>` from `-%>` and `_%>`. The mapping
  -- falls through to `vim.lsp.buf.hover()` (html-lsp / ts_ls are attached to
  -- EJS buffers) whenever the cursor is not on a delimiter.
  hover = true,
}

--- Severity strings accepted by the diagnostic settings.
local SEVERITIES = {
  error = vim.diagnostic.severity.ERROR,
  warn = vim.diagnostic.severity.WARN,
  warning = vim.diagnostic.severity.WARN,
  info = vim.diagnostic.severity.INFO,
  information = vim.diagnostic.severity.INFO,
  hint = vim.diagnostic.severity.HINT,
}

--- Resolves a configured severity to a `vim.diagnostic.severity` value, or nil
--- when the check is switched off. Anything unrecognised falls back to the
--- default rather than erroring: a typo in settings should not cost you the
--- check entirely.
---@param value string|boolean|nil
---@return integer? severity
function M.severity(value)
  if value == nil then
    return vim.diagnostic.severity.WARN
  end
  if value == false or value == 'off' then
    return nil
  end
  if value == true then
    return vim.diagnostic.severity.WARN
  end
  return SEVERITIES[tostring(value):lower()] or vim.diagnostic.severity.WARN
end

--- Normalises a user config table, applying back-compat for options that have
--- moved. `diagnostics = true|false` (the pre-1.2.0 spelling, before the two
--- checks got separate severities) still turns both checks on or off.
---@param opts table?
---@return table
function M.normalize(opts)
  opts = vim.deepcopy(opts or {})

  if type(opts.diagnostics) == 'boolean' then
    local value = opts.diagnostics and 'warn' or 'off'
    opts.diagnostics = { missing_include = value, broken_comment = value }
  end

  return opts
end

--- True when at least one diagnostic check is switched on.
---@param diagnostics table|boolean|nil
---@return boolean
function M.diagnostics_enabled(diagnostics)
  if diagnostics == nil then
    return true
  end
  if type(diagnostics) == 'boolean' then
    return diagnostics
  end
  return M.severity(diagnostics.missing_include) ~= nil or M.severity(diagnostics.broken_comment) ~= nil
end

return M
