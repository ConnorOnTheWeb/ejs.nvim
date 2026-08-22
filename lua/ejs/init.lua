local M = {}

local _config = {}

--- Returns the active configuration table.
--- Only valid after setup() has been called.
---@return table
function M.get_config()
  return _config
end

--- Sets up ejs.nvim.
--- Safe to call multiple times; subsequent calls after the first are no-ops.
---@param opts? table Optional overrides for the default config.
function M.setup(opts)
  if vim.g.loaded_ejs_nvim then
    return
  end
  vim.g.loaded_ejs_nvim = true

  local config = require('ejs.config')
  _config = vim.tbl_deep_extend('force', config.defaults, config.normalize(opts))

  if _config.treesitter then
    require('ejs.treesitter').setup()
  end

  if _config.lsp then
    require('ejs.lsp').setup()
  end

  if _config.snippets then
    require('ejs.snippets').setup()
  end

  if _config.completion.cmp then
    require('ejs.cmp').setup()
  end

  if _config.completion.blink then
    require('ejs.blink').setup()
  end

  if _config.completion.omni then
    require('ejs.omni').setup()
  end

  if config.diagnostics_enabled(_config.diagnostics) then
    require('ejs.diagnostics').setup()
  end

  if _config.comment then
    require('ejs.comment').setup()
  end

  if _config.folding then
    require('ejs.fold').setup()
  end

  if _config.hover then
    require('ejs.hover').setup()
  end
end

--- Documentation for the EJS delimiter under the cursor. Returns false when
--- the cursor is not on one, so a custom `K` mapping can fall through.
---@return boolean handled
function M.hover()
  return require('ejs.hover').hover()
end

--- Jumps to the file referenced by the `include()` under the cursor.
--- Returns false when the cursor is not on an include path, so a custom
--- mapping can fall through.
---@return boolean handled
function M.goto_definition()
  return require('ejs.include').goto_definition()
end

return M
