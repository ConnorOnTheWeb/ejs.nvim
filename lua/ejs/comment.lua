-- Commenting EJS, which is five different operations wearing one keymap.
--
-- `commentstring` is a single string, and `gc` applies it to whatever the
-- cursor is on. That is fine for a language with one comment syntax. An EJS
-- template is made of five distinguishable line shapes and only one of them
-- takes `<%# … %>`, so a flat comment string is wrong on four of them —
-- measured, not assumed: three of the five produce a template that either
-- throws or silently keeps evaluating the code it was supposed to remove.
--
--   Where the line is        Style                Result
--   ----------------------   ------------------   ---------------------------
--   Markup or text           `<%# … %>` wrap      <p>Hi</p> -> <%# <p>Hi</p> %>
--   One whole EJS tag        `#` on the tag       <% if (a) { %> -> <%#if (a) { %>
--   Markup carrying a tag    one-line dead branch <p><%= x %></p> -> <% if (false) { %>…<% } %>
--   Inside a scriptlet body  `//` prefix          const a = 1; -> // const a = 1;
--   Only a delimiter         left alone           <% -> <%
--
-- Ported from ejs-colorizer v2.5.0, which arrived at the same table by
-- compiling every result with the real EJS engine. This module is tested the
-- same way (tests/comment_render_spec.lua), because the third bug that
-- methodology found was invisible from the output string alone.
--
-- Why the dead branch rather than `<%#` on a line carrying a tag: EJS scans
-- from `<%#` to the *first* `%>`, so the comment closes at the inner tag's
-- own `%>` and the rest leaks back into the template. Under EJS 6 that is not
-- cosmetic — it throws `Could not find matching close tag for "<%#"`. The
-- `%%>` literal escape does not help; the comment scanner does not honour it.
local M = {}

local region = require('ejs.region')

--- The dead branch, which is the only EJS construct that suppresses a line
--- containing a tag. Also the buffer's `commentstring`, as the fallback for
--- anything that bypasses these mappings.
M.DEAD_OPEN = '<% if (false) { %>'
M.DEAD_CLOSE = '<% } %>'

--- Splits a line into its indent and the rest.
---@param text string
---@return string indent, string body
local function split_indent(text)
  local indent, body = text:match('^([ \t]*)(.*)$')
  return indent or '', body or ''
end

--- Complete `<% … %>` spans on one line.
---
--- `<%%` is the v6 literal escape and opens nothing, so it is skipped rather
--- than counted — the same rule region.lua's scanner applies.
---@param text string
---@return integer count, string outside Text with every complete tag removed
local function tags_on_line(text)
  local count, outside = 0, {}
  local i, n = 1, #text

  while i <= n do
    if text:sub(i, i + 2) == '<%%' then
      table.insert(outside, '<%%')
      i = i + 3
    elseif text:sub(i, i + 1) == '<%' then
      local close = text:find('%%>', i + 2)
      if close then
        count = count + 1
        i = close + 2
      else
        -- An unterminated opener is not a complete tag; the rest of the line
        -- is inside it and is not markup either way.
        table.insert(outside, text:sub(i))
        break
      end
    else
      table.insert(outside, text:sub(i, i))
      i = i + 1
    end
  end

  return count, (table.concat(outside):gsub('^%s*(.-)%s*$', '%1'))
end

--- True for a line that is nothing but a tag delimiter.
---
--- Commenting one of these is what the extension's 2.5.0 notes call the worst
--- case: it changes the block structure the rest of the selection was
--- classified against, so the scriptlet body around it stops reading as code
--- and the next toggle comments it again instead of uncommenting.
local function delimiter_only(body)
  return body:match('^<%%[-=_#]?$') ~= nil or body:match('^[-_]?%%>$') ~= nil
end

--- Which of the five shapes a line is.
---@param lines string[] All buffer lines
---@param lnum integer 1-indexed
---@param regions table[] Code regions, 0-indexed
---@return 'markup'|'whole_tag'|'markup_with_tag'|'code'|'delimiter'
function M.classify(lines, lnum, regions)
  local text = lines[lnum] or ''
  local _, body = split_indent(text)

  if body == '' then
    return 'markup'
  end

  if delimiter_only(body) then
    return 'delimiter'
  end

  local row = lnum - 1
  local first_col = #text - #body
  local inside_code = region.contains(regions, row, first_col)

  if inside_code then
    -- A code line carrying the closing `%>` is left alone: commenting it out
    -- would take the delimiter with it.
    if body:find('%%>') then
      return 'delimiter'
    end
    return 'code'
  end

  local count, outside = tags_on_line(body)
  if count == 0 then
    return 'markup'
  end
  if count == 1 and outside == '' then
    return 'whole_tag'
  end
  return 'markup_with_tag'
end

--------------------------------------------------------------------------------
-- One line, one shape
--------------------------------------------------------------------------------

--- Characters that are part of an EJS opening delimiter rather than content.
--- `#` is here so a doubled marker (`<%##`) unwinds one level at a time.
local MARKER_CHARS = { ['='] = true, ['-'] = true, ['_'] = true, ['#'] = true }

--- Which commenting style produced this line, or nil when it is not commented.
---
--- Detected from the text rather than from `classify`, because commenting
--- changes what a line classifies as: `<p>Hi</p>` is markup, and once wrapped
--- to `<%# <p>Hi</p> %>` it is a whole tag. Uncommenting off the new shape
--- would strip the wrong delimiters.
---
--- The wrap style always leaves a space after `<%#` and the marker style never
--- does, so the character at index 3 separates them with no guessing about
--- whether the content "looks like" JavaScript.
---@param body string
---@param shape string
---@return string? style
function M.comment_style(body, shape)
  if body:sub(1, #M.DEAD_OPEN) == M.DEAD_OPEN and body:sub(-#M.DEAD_CLOSE) == M.DEAD_CLOSE then
    return 'markup_with_tag'
  end
  if body:match('^<%%# ') and body:match(' %%>$') then
    return 'markup'
  end
  if body:match('^<%%#') then
    return 'whole_tag'
  end
  if shape == 'code' and body:match('^//') then
    return 'code'
  end
  return nil
end

--- Comments one line body in the style its shape calls for.
---@param body string
---@param shape string
---@return string
function M.comment_body(body, shape)
  if shape == 'code' then
    return '// ' .. body
  end
  if shape == 'markup' then
    return '<%# ' .. body .. ' %>'
  end
  if shape == 'whole_tag' then
    -- The marker consumes the space after `<%`, which is what keeps this
    -- distinguishable from the wrap style. A delimiter marker (`=`, `-`, `_`)
    -- is part of the original tag and is preserved: `<%= x %>` becomes
    -- `<%#= x %>` and toggles back to `<%= x %>`, not to a scriptlet that
    -- cannot parse.
    if body:sub(3, 3) == ' ' then
      return '<%#' .. body:sub(4)
    end
    return '<%#' .. body:sub(3)
  end
  if shape == 'markup_with_tag' then
    return M.DEAD_OPEN .. body .. M.DEAD_CLOSE
  end
  return body
end

--- Removes one level of commenting, or returns the body unchanged.
---@param body string
---@param shape string
---@return string
function M.uncomment_body(body, shape)
  if shape == 'code' then
    return (body:gsub('^//%s?', '', 1))
  end
  if shape == 'markup' then
    local inner = body:match('^<%%# (.*) %%>$')
    return inner or body
  end
  if shape == 'whole_tag' then
    -- Commenting an already-commented whole tag adds a second marker rather
    -- than a second wrap, so uncommenting removes exactly one — and restores
    -- the space the marker consumed, unless what follows is itself part of the
    -- delimiter.
    local rest = body:sub(4)
    if MARKER_CHARS[rest:sub(1, 1)] then
      return '<%' .. rest
    end
    return '<% ' .. rest
  end
  if shape == 'markup_with_tag' then
    return body:sub(#M.DEAD_OPEN + 1, #body - #M.DEAD_CLOSE)
  end
  return body
end

--------------------------------------------------------------------------------
-- Toggling a range
--------------------------------------------------------------------------------

--- Classification for every line in a range, skipping the ones nothing can be
--- done to.
local function plan(bufnr, first, last)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local regions = region.code_regions(bufnr, { include_comments = true })

  local entries = {}
  for lnum = first, last do
    local text = lines[lnum]
    if text ~= nil then
      local shape = M.classify(lines, lnum, regions)
      local indent, body = split_indent(text)
      -- A blank line has nothing to comment and would otherwise become a
      -- comment containing nothing.
      if shape ~= 'delimiter' and body ~= '' then
        table.insert(entries, { lnum = lnum, indent = indent, body = body, shape = shape })
      end
    end
  end
  return entries
end

--- Toggles comments across a 1-indexed inclusive line range.
---
--- Comments unless every commentable line in the range is already commented,
--- which is the `gc` convention and the extension's.
---@param bufnr integer
---@param first integer
---@param last integer
---@return integer changed Number of lines rewritten
function M.toggle(bufnr, first, last)
  local entries = plan(bufnr, first, last)
  if #entries == 0 then
    return 0
  end

  local all_commented = true
  for _, entry in ipairs(entries) do
    entry.style = M.comment_style(entry.body, entry.shape)
    if not entry.style then
      all_commented = false
    end
  end

  for _, entry in ipairs(entries) do
    -- Uncommenting goes by the style that produced the line; commenting goes
    -- by the shape the line is. Those are different questions and using one
    -- for the other is what breaks the round trip.
    local body = all_commented and M.uncomment_body(entry.body, entry.style)
      or M.comment_body(entry.body, entry.shape)
    vim.api.nvim_buf_set_lines(bufnr, entry.lnum - 1, entry.lnum, false, { entry.indent .. body })
  end

  return #entries
end

--------------------------------------------------------------------------------
-- Mappings
--------------------------------------------------------------------------------

--- `operatorfunc` target for the `gc` operator.
function M.operator()
  local first = vim.api.nvim_buf_get_mark(0, '[')[1]
  local last = vim.api.nvim_buf_get_mark(0, ']')[1]
  M.toggle(vim.api.nvim_get_current_buf(), first, last)
end

--- Installs the buffer-local comment mappings.
---
--- `gc` and `gcc` are overridden rather than left to `commentstring`, because
--- a single comment string cannot be right for five line shapes. Everything
--- that bypasses these — a plugin driving `commentstring` directly, a macro,
--- another editor — still gets the dead branch, which is the strictly better
--- static fallback: it compiles on any markup selection whether or not there
--- is a tag in it, where `<%#` compiled only when there was not.
---@param bufnr integer
function M.setup_buffer(bufnr)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
  end

  map('n', 'gcc', function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local count = vim.v.count1
    M.toggle(bufnr, lnum, lnum + count - 1)
  end, 'Toggle EJS comment (line)')

  -- `expr` so the returned `g@` is executed as the operator, which is what
  -- lets `gcip`, `gc3j` and the rest work without enumerating motions.
  vim.keymap.set('n', 'gc', function()
    vim.o.operatorfunc = "v:lua.require'ejs.comment'.operator"
    return 'g@'
  end, { buffer = bufnr, expr = true, silent = true, desc = 'Toggle EJS comment (operator)' })

  map('x', 'gc', function()
    -- Leave visual mode so the '< '> marks are set, then act on them.
    vim.cmd('normal! \27')
    local first = vim.api.nvim_buf_get_mark(bufnr, '<')[1]
    local last = vim.api.nvim_buf_get_mark(bufnr, '>')[1]
    M.toggle(bufnr, first, last)
  end, 'Toggle EJS comment (visual)')
end

--- Attaches the comment mappings to EJS buffers.
function M.setup()
  local group = vim.api.nvim_create_augroup('ejs_comment', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'ejs',
    desc = 'ejs.nvim: shape-aware gc / gcc',
    callback = function(args)
      M.setup_buffer(args.buf)
    end,
  })

  -- setup() usually runs from the FileType autocommand that has already fired
  -- for the current buffer, so that buffer is handled directly.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'ejs' then
      M.setup_buffer(bufnr)
    end
  end
end

return M
