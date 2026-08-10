-- blink.cmp adapter. All completion logic lives in lua/ejs/completion.lua;
-- this file only translates between that core and blink's source protocol.
--
-- blink builds a source by calling `require(<module>).new(opts, config)`, so
-- `M.new` is the entry point and the returned instance carries the methods.
local M = {}

local source = {}
source.__index = source

--- @param opts table Options from `sources.providers.ejs.opts`
function M.new(opts)
  return setmetatable({ opts = opts or {} }, source)
end

function source:enabled()
  return require('ejs.completion').enabled_for_buf(vim.api.nvim_get_current_buf())
end

function source:get_trigger_characters()
  return require('ejs.completion').trigger_characters
end

function source:get_completions(context, callback)
  local completion = require('ejs.completion')

  local row, col = context.cursor[1], context.cursor[2]
  local ctx = completion.get_context(context.line:sub(1, col), { bufnr = context.bufnr, row = row })

  local items = {}
  local incomplete = false
  if ctx then
    -- Unfiltered on purpose: blink fuzzy-matches these itself.
    items = completion.lsp_items(ctx, context.bufnr, row)
    -- Path completion has to be re-requested as the user walks into a
    -- directory, since the candidate set changes with the prefix.
    incomplete = ctx.kind == 'include'
  end

  callback({
    items = items,
    is_incomplete_forward = incomplete,
    is_incomplete_backward = incomplete,
  })

  return function() end
end

--- Registers the source with blink.cmp for the `ejs` filetype.
---@return boolean registered
function M.setup()
  local ok, blink = pcall(require, 'blink.cmp')
  if not ok then
    return false
  end

  if type(blink.add_source_provider) ~= 'function' or type(blink.add_filetype_source) ~= 'function' then
    return false
  end

  if vim.g.ejs_blink_registered then
    return true
  end
  vim.g.ejs_blink_registered = true

  local registered = pcall(blink.add_source_provider, 'ejs', {
    name = 'EJS',
    module = 'ejs.blink',
  })
  if not registered then
    return false
  end

  pcall(blink.add_filetype_source, 'ejs', 'ejs')
  return true
end

return M
