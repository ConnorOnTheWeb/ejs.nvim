-- Where the EJS code regions are in a buffer.
--
-- This exists because an `include()` call is only ever inside an EJS tag, and
-- anything that acts on include paths has to know that. Scanning the whole
-- buffer for `include(`-shaped text reports prose, HTML comments and body
-- copy as broken includes; tightening the pattern does not fix it, because a
-- guard has to enumerate the ways text can fail to be code and that set has
-- no end. The invariant that settles it is structural, so it is answered
-- structurally, once, here.
--
-- `<%# %>` comments are regions too, but a separate kind. Callers must say
-- which they want: `include_comments` has no default, so a new caller has to
-- state its intent rather than silently inherit the wrong one.
local M = {}

--- The parser name. `ejs` is only a filetype alias for it (lua/ejs/treesitter.lua).
M.LANGUAGE = 'embedded_template'

--- Cached compiled queries, one per `include_comments` setting.
local queries = {}

local function region_query(include_comments)
  local key = include_comments and 'both' or 'code'
  if queries[key] == nil then
    local source = include_comments and '(code) @region (comment) @region' or '(code) @region'
    local ok, query = pcall(vim.treesitter.query.parse, M.LANGUAGE, source)
    queries[key] = ok and query or false
  end
  return queries[key] or nil
end

--- Code regions from the real parse tree, or nil when the parser is unavailable.
---
--- Returns nil rather than an empty list on failure, so the caller can tell
--- "no parser" from "no tags in this buffer".
---@param bufnr integer
---@param include_comments boolean
---@return table[]? regions
function M.treesitter_regions(bufnr, include_comments)
  local query = region_query(include_comments)
  if not query then
    return nil
  end

  -- The language is passed explicitly rather than resolved from the filetype,
  -- so this works before `treesitter.setup()` has registered the alias and
  -- when the user has turned that module off.
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, M.LANGUAGE)
  if not ok or not parser then
    return nil
  end

  local parsed, trees = pcall(parser.parse, parser)
  if not parsed or type(trees) ~= 'table' or not trees[1] then
    return nil
  end

  local regions = {}
  for _, node in query:iter_captures(trees[1]:root(), bufnr, 0, -1) do
    local start_row, start_col, end_row, end_col = node:range()
    table.insert(regions, { start_row, start_col, end_row, end_col })
  end
  return regions
end

--- How far past `<%` the code inside a tag begins, for each opener.
local INNER_OFFSET = { ['='] = 3, ['-'] = 3, ['#'] = 3, ['_'] = 3 }

--- Code regions found by scanning the text for `<% %>` spans.
---
--- The fallback for when the `embedded_template` parser is not installed.
--- `:checkhealth ejs` reports that as an Error, but the plugin still loads and
--- everything else still works, and `find_includes` also drives
--- `:EjsDefinition` — so reporting nothing here would turn a false-positive
--- bug into a missing feature. This is deliberately the same shape and return
--- type as the Tree-sitter path so the two cannot drift.
---@param lines string[]
---@param include_comments boolean
---@return table[] regions
function M.scan_regions(lines, include_comments)
  local regions = {}
  local open = nil

  local function close_at(end_row, end_col)
    if open.kind == 'code' or include_comments then
      table.insert(regions, { open.row, open.col, end_row, end_col })
    end
    open = nil
  end

  for index, line in ipairs(lines) do
    local row = index - 1
    local from = 1

    while true do
      if open then
        local close = line:find('%%>', from)
        if not close then
          break
        end
        close_at(row, close - 1)
        from = close + 2
      else
        local start = line:find('<%%', from)
        if not start then
          break
        end
        local third = line:sub(start + 2, start + 2)
        if third == '%' then
          -- `<%%` is the v6 literal escape, not a tag. The Tree-sitter grammar
          -- produces no code node for it either.
          from = start + 3
        else
          local inner = start + (INNER_OFFSET[third] or 2)
          open = { row = row, col = inner - 1, kind = third == '#' and 'comment' or 'code' }
          from = inner
        end
      end
    end
  end

  -- An unterminated tag runs to the end of the buffer, which is also what the
  -- parser does with one. Mid-edit that is the right answer: the include being
  -- typed is inside a tag the author has not finished closing yet.
  if open then
    local last = #lines
    close_at(math.max(last - 1, 0), #(lines[last] or ''))
  end

  return regions
end

--- Every EJS code region in a buffer, as 0-indexed half-open ranges
--- `{ start_row, start_col, end_row, end_col }`.
---@param bufnr integer
---@param opts table `{ include_comments = boolean }`, required
---@return table[] regions
function M.code_regions(bufnr, opts)
  if type(opts) ~= 'table' or opts.include_comments == nil then
    error('ejs.region: opts.include_comments must be stated explicitly', 2)
  end

  local regions = M.treesitter_regions(bufnr, opts.include_comments)
  if regions then
    return regions
  end
  return M.scan_regions(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), opts.include_comments)
end

--- True when a 0-indexed position falls inside one of `regions`.
---@param regions table[]
---@param row integer
---@param col integer
---@return boolean
function M.contains(regions, row, col)
  for _, region in ipairs(regions) do
    local start_row, start_col, end_row, end_col = region[1], region[2], region[3], region[4]
    local after_start = row > start_row or (row == start_row and col >= start_col)
    local before_end = row < end_row or (row == end_row and col < end_col)
    if after_start and before_end then
      return true
    end
  end
  return false
end

--- True when the cursor is inside a `(code)` node, meaning inside a `<% %>`
--- tag. False for `(content)` nodes (plain HTML) and when no parser is active.
---
--- The cursor form of the same question `code_regions` answers for a range.
--- It stays a `get_node()` walk because that is cheaper than collecting every
--- region to test one position, and unlike `find_includes` its callers want
--- false when there is no parser.
---@return boolean
function M.cursor_in_code_node()
  local node = vim.treesitter.get_node()
  while node do
    if node:type() == 'code' then
      return true
    end
    node = node:parent()
  end
  return false
end

return M
