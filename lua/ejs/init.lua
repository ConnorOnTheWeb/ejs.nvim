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

  _config = vim.tbl_deep_extend('force', require('ejs.config').defaults, opts or {})

  if _config.treesitter then
    require('ejs.treesitter').setup()
  end

  if _config.lsp then
    require('ejs.lsp').setup()
  end

  if _config.snippets then
    require('ejs.snippets').setup()
  end
end

return M
