-- Complete-function adapter, for every engine with no source API of its own:
-- Neovim 0.12's built-in `vim.o.autocomplete`, mini.completion, coq_nvim, and
-- plain `i_CTRL-X_CTRL-O`.
--
-- On 0.12 the function is chained into 'complete', which leaves `omnifunc`
-- with whatever owns it — usually html-lsp or ts_ls, which lua/ejs/lsp.lua
-- attaches to every EJS buffer. Only on older versions, and only when nothing
-- else has claimed it, is `omnifunc` set instead.
local M = {}

local pending = nil

--- 'complete' takes a function name or a Funcref, not an expression, so a
--- `v:lua.require'...'` reference cannot be used there. The `F{func}` spelling
--- in `:help 'complete'` is notation — the braces are not typed.
local FUNCTION_NAME = 'EjsCompleteFunc'

--- `omnifunc`/`completefunc`/`'complete'` implementation.
---@param findstart integer
---@param base string
---@return integer|table
function M.omnifunc(findstart, base)
  local completion = require('ejs.completion')

  if findstart == 1 then
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local ctx = completion.get_context(vim.api.nvim_get_current_line():sub(1, col), {
      bufnr = vim.api.nvim_get_current_buf(),
      row = row,
    })
    if not ctx then
      pending = nil
      return -3
    end
    pending = ctx
    return ctx.start_col
  end

  local ctx = pending
  if not ctx then
    return { words = {} }
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local use_snippets = (require('ejs').get_config().completion or {}).snippets ~= false and vim.snippet ~= nil

  local results = {}
  for _, item in ipairs(completion.items(ctx, bufnr)) do
    if base == '' or vim.startswith(item.label:lower(), base:lower()) then
      table.insert(results, {
        word = item.label,
        abbr = item.label,
        kind = item.detail or '',
        menu = 'EJS',
        info = completion.documentation(item),
        user_data = (use_snippets and item.snippet) and vim.json.encode({
          ejs_snippet = item.snippet,
          ejs_word = item.label,
        }) or '',
      })
    end
  end

  -- Path completion in particular has to be recomputed as the leading text
  -- changes, which is what refresh = 'always' asks for.
  return { words = results, refresh = 'always' }
end

--- Expands the snippet body of an accepted item, since the complete-function
--- protocol can only insert plain text.
local function on_complete_done()
  local completed = vim.v.completed_item
  if not completed or completed.user_data == nil or completed.user_data == '' then
    return
  end

  local ok, decoded = pcall(vim.json.decode, completed.user_data)
  if not ok or type(decoded) ~= 'table' or not decoded.ejs_snippet then
    return
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local word = decoded.ejs_word or ''
  local start_col = col - #word
  if start_col < 0 or vim.api.nvim_get_current_line():sub(start_col + 1, col) ~= word then
    return
  end

  vim.api.nvim_buf_set_text(0, row - 1, start_col, row - 1, col, { '' })
  vim.snippet.expand(decoded.ejs_snippet)
end

local function define_vim_function()
  if vim.fn.exists('*' .. FUNCTION_NAME) == 1 then
    return
  end
  vim.cmd(([[
    function! %s(findstart, base) abort
      return v:lua.require'ejs.omni'.omnifunc(a:findstart, a:base)
    endfunction
  ]]):format(FUNCTION_NAME))
end

--- Wires the complete-function into EJS buffers.
function M.setup()
  local group = vim.api.nvim_create_augroup('ejs_omni', { clear = true })
  define_vim_function()

  local function attach(bufnr)
    vim.api.nvim_buf_call(bufnr, function()
      if vim.fn.has('nvim-0.12') == 1 then
        local flag = 'F' .. FUNCTION_NAME
        if not vim.tbl_contains(vim.opt_local.complete:get(), flag) then
          vim.opt_local.complete:append(flag)
        end
      elseif vim.bo[bufnr].omnifunc == '' then
        vim.bo[bufnr].omnifunc = "v:lua.require'ejs.omni'.omnifunc"
      end
    end)
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'ejs',
    desc = 'ejs.nvim: complete-function for built-in completion',
    callback = function(args)
      attach(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd('CompleteDone', {
    group = group,
    pattern = '*',
    desc = 'ejs.nvim: expand the accepted snippet',
    callback = function(args)
      if vim.bo[args.buf].filetype == 'ejs' and vim.snippet then
        on_complete_done()
      end
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'ejs' then
      attach(bufnr)
    end
  end
end

return M
