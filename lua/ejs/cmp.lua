-- nvim-cmp adapter. All completion logic lives in lua/ejs/completion.lua;
-- this file only translates between that core and nvim-cmp's source protocol.
local M = {}

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return require('ejs.completion').enabled_for_buf(vim.api.nvim_get_current_buf())
end

function source:get_debug_name()
  return 'ejs'
end

function source:get_trigger_characters()
  return require('ejs.completion').trigger_characters
end

--- Includes `<`, `%` and `/` so a partially typed tag or path segment counts
--- as one keyword. Items carry an explicit textEdit regardless.
function source:get_keyword_pattern()
  return [[\%(<%\?[=#_-]\?\|[A-Za-z_][A-Za-z0-9_./-]*\)]]
end

function source:complete(params, callback)
  local completion = require('ejs.completion')
  local ctx = completion.get_context(params.context.cursor_before_line, {
    bufnr = params.context.bufnr,
    row = params.context.cursor.row,
  })
  if not ctx then
    return callback({ items = {}, isIncomplete = false })
  end

  local items = completion.lsp_items(ctx, params.context.bufnr, params.context.cursor.row)
  -- Directory items re-trigger so navigating into a folder keeps completing.
  callback({ items = items, isIncomplete = ctx.kind == 'include' })
end

--- Registers the `ejs` nvim-cmp source. No-ops silently if nvim-cmp is not
--- installed.
---@return boolean registered
function M.setup()
  local ok, cmp = pcall(require, 'cmp')
  if not ok then
    return false
  end
  cmp.register_source('ejs', source.new())
  return true
end

return M
