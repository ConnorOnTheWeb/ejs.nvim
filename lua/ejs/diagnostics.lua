-- Diagnostics for EJS templates, ported from ejs-colorizer's
-- diagnosticProvider.ts:
--
--   * an `include()` whose path does not resolve to a file on disk
--   * a `<%# %>` comment that terminates earlier than it looks like it does
--
-- The JavaScript syntax check the extension also performs is deliberately not
-- ported: `ts_ls` is already attached to `<% %>` regions by lua/ejs/lsp.lua
-- and reports real syntax errors there with better positions than a
-- joined-program heuristic can.
local M = {}

local namespace = vim.api.nvim_create_namespace('ejs')

--- Finds `<%#` comments whose content closes the tag before the author meant
--- it to.
---
--- EJS scans from `<%#` to the *first* `%>`. When the commented-out text
--- itself contains a tag — the usual case, commenting out a line holding
--- `<%= value %>` — the comment ends at that tag's `%>` and the remainder
--- leaks back into the template as markup.
---@param bufnr integer
---@return table[]
local function broken_comments(bufnr)
  local diagnostics = {}

  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local from = 1
    while true do
      local start = line:find('<%%#', from)
      if not start then
        break
      end

      local close = line:find('%%>', start + 3)
      if close then
        local content = line:sub(start + 3, close - 1)
        if content:find('<%%') then
          table.insert(diagnostics, {
            lnum = lnum - 1,
            col = start - 1,
            end_lnum = lnum - 1,
            end_col = close + 1,
            severity = vim.diagnostic.severity.WARN,
            source = 'ejs',
            message = 'This <%# %> comment ends early: the tag inside it closes the comment at its own %>. '
              .. 'Wrap the block in <% if (false) { %> ... <% } %> instead.',
          })
        end
        from = close + 2
      else
        break
      end
    end
  end

  return diagnostics
end

--- Diagnostics for one buffer, without publishing them.
---@param bufnr integer
---@return table[]
function M.collect(bufnr)
  local include = require('ejs.include')
  local diagnostics = {}

  -- A warning about an include you commented out is noise you didn't ask for,
  -- so `<%# %>` is excluded here and only here — `:EjsDefinition` still
  -- follows one.
  for _, entry in ipairs(include.find_includes(bufnr, { include_comments = false })) do
    if entry.raw ~= '' then
      local resolved = include.resolve(entry.raw, bufnr)
      if not resolved then
        table.insert(diagnostics, {
          lnum = entry.lnum,
          col = entry.col,
          end_lnum = entry.lnum,
          end_col = entry.end_col,
          severity = vim.diagnostic.severity.WARN,
          source = 'ejs',
          message = ("No file found for include('%s'). Looked in: %s"):format(
            entry.raw,
            table.concat(
              vim.tbl_map(function(root)
                return vim.fn.fnamemodify(root, ':~:.')
              end, include.search_roots(bufnr)),
              ', '
            )
          ),
        })
      end
    end
  end

  vim.list_extend(diagnostics, broken_comments(bufnr))
  return diagnostics
end

--- Recomputes and publishes diagnostics for a buffer.
---@param bufnr integer
function M.refresh(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= 'ejs' then
    return
  end
  vim.diagnostic.set(namespace, bufnr, M.collect(bufnr))
end

--- Attaches the diagnostic pass to EJS buffers, debounced while typing.
function M.setup()
  local group = vim.api.nvim_create_augroup('ejs_diagnostics', { clear = true })
  local timers = {}

  local function schedule(bufnr)
    if timers[bufnr] then
      timers[bufnr]:stop()
      timers[bufnr]:close()
    end
    local timer = vim.uv.new_timer()
    timers[bufnr] = timer
    timer:start(
      500,
      0,
      vim.schedule_wrap(function()
        if timers[bufnr] then
          timers[bufnr]:stop()
          timers[bufnr]:close()
          timers[bufnr] = nil
        end
        M.refresh(bufnr)
      end)
    )
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'ejs',
    desc = 'ejs.nvim: include-path and comment diagnostics',
    callback = function(args)
      M.refresh(args.buf)
      vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave', 'BufWritePost' }, {
        group = group,
        buffer = args.buf,
        callback = function()
          schedule(args.buf)
        end,
      })
    end,
  })

  -- setup() usually runs from the FileType autocommand that has already fired
  -- for the current buffer, so that buffer is handled directly.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'ejs' then
      M.refresh(bufnr)
    end
  end
end

return M
