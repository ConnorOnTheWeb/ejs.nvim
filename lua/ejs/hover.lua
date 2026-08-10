-- Hover documentation for EJS tag delimiters, ported from ejs-colorizer's
-- hoverProvider.ts.
--
-- The distinction this exists to explain is `<%=` versus `<%-` (escaped vs
-- unescaped output, i.e. the XSS-relevant one) and `%>` versus `-%>` versus
-- `_%>`, none of which is guessable from the syntax.
--
-- `K` in an EJS buffer already belongs to html-lsp or ts_ls, which
-- lua/ejs/lsp.lua attaches to every EJS buffer, so the mapping installed here
-- answers only on a delimiter and hands off everywhere else.
local M = {}

--- Finds the delimiter under the cursor, if any.
---
--- Openers are matched longest-first so `<%=` is not read as `<%` with a
--- stray `=`, and `<%%` is not read as `<%` either.
---@return table? entry
---@return string? token
function M.resolve()
  local completion = require('ejs.completion')
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1

  local candidates = {}
  for _, tag in ipairs(completion.tags) do
    table.insert(candidates, tag)
  end
  for _, tag in ipairs(completion.close_tags) do
    table.insert(candidates, tag)
  end
  table.sort(candidates, function(a, b)
    return #a.label > #b.label
  end)

  for _, candidate in ipairs(candidates) do
    local width = #candidate.label
    -- The cursor counts as "on" the delimiter anywhere within it, so scan
    -- every start position that could still cover the cursor column.
    for start = math.max(1, col - width + 1), col do
      if line:sub(start, start + width - 1) == candidate.label then
        return candidate, candidate.label
      end
    end
  end

  return nil
end

--- Shows the EJS hover float for the delimiter under the cursor.
---@return boolean handled
function M.hover()
  local entry = M.resolve()
  if not entry then
    return false
  end

  local markdown = ('**`%s`** — %s\n\n%s'):format(entry.label, entry.detail, entry.desc)

  vim.lsp.util.open_floating_preview(vim.split(markdown, '\n'), 'markdown', {
    border = 'rounded',
    focusable = true,
    focus_id = 'ejs-hover',
    max_width = 80,
  })
  return true
end

---@param bufnr integer
local function map(bufnr)
  vim.keymap.set('n', 'K', function()
    if M.hover() then
      return
    end
    if #vim.lsp.get_clients({ bufnr = bufnr }) > 0 then
      vim.lsp.buf.hover()
    else
      vim.cmd('normal! K')
    end
  end, { buffer = bufnr, desc = 'EJS tag hover (falls back to LSP/keywordprg)' })
end

--- Maps `K` in EJS buffers, falling through when the cursor is not on a
--- delimiter.
function M.setup()
  local group = vim.api.nvim_create_augroup('ejs_hover', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'ejs',
    desc = 'ejs.nvim: hover documentation on K',
    callback = function(args)
      map(args.buf)
    end,
  })

  -- setup() usually runs from the FileType autocommand that has already fired
  -- for the current buffer, so that buffer needs mapping directly.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'ejs' then
      map(bufnr)
    end
  end
end

return M
