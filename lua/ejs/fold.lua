-- Folding for EJS control-flow blocks.
--
-- Tree-sitter folding cannot express these: `<% if (x) { %>` and `<% } %>`
-- are two independent `directive` nodes in the embedded_template grammar with
-- the HTML between them belonging to neither, so there is no single node
-- spanning the block. Brace depth inside the code regions is what actually
-- delimits it, which is what this computes.
local M = {}

--- Net brace depth change contributed by the EJS code regions on one line.
---
--- Only text inside `<% %>` counts: a `{` in markup or in a CSS block is not
--- a control-flow brace. Braces inside strings and comments within the code
--- are skipped so `<% const s = "}" %>` does not unbalance the file.
---@param line string
---@return integer
function M.line_delta(line)
  local delta = 0
  local from = 1

  while true do
    local open = line:find('<%%', from)
    if not open then
      break
    end
    -- `<%%` is the literal-escape sequence, not a tag.
    if line:sub(open + 2, open + 2) == '%' then
      from = open + 3
    else
      local close = line:find('%%>', open + 2)
      local code = line:sub(open + 2, (close or (#line + 1)) - 1)

      local quote = nil
      local i = 1
      while i <= #code do
        local c = code:sub(i, i)
        if quote then
          if c == '\\' then
            i = i + 1
          elseif c == quote then
            quote = nil
          end
        elseif c == '"' or c == "'" or c == '`' then
          quote = c
        elseif c == '/' and code:sub(i + 1, i + 1) == '/' then
          break
        elseif c == '{' then
          delta = delta + 1
        elseif c == '}' then
          delta = delta - 1
        end
        i = i + 1
      end

      if not close then
        break
      end
      from = close + 2
    end
  end

  return delta
end

--- Per-buffer cache of the running depth before each line, rebuilt whenever
--- the buffer changes. Without it, `foldexpr` would be O(lines) per line.
local cache = {}

local function depths(bufnr)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local entry = cache[bufnr]
  if entry and entry.tick == tick then
    return entry.depths
  end

  local before = {}
  local depth = 0
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    before[lnum] = depth
    depth = depth + M.line_delta(line)
  end

  cache[bufnr] = { tick = tick, depths = before }
  return before
end

--- `foldexpr` for EJS buffers.
---
--- A line's level is the greater of the depth before and after it, so the
--- opening `<% if { %>` and the closing `<% } %>` are both inside the fold
--- rather than dangling outside it.
---@param lnum integer 1-indexed
---@return string|integer
function M.foldexpr(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local before = depths(bufnr)[lnum]
  if not before then
    return 0
  end
  local after = before + M.line_delta(vim.fn.getline(lnum))
  return math.max(before, after)
end

--- Applies the fold settings to a buffer, leaving folds open.
---@param bufnr integer
function M.attach(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.opt_local.foldmethod = 'expr'
    vim.opt_local.foldexpr = "v:lua.require'ejs.fold'.foldexpr(v:lnum)"
    -- Opening a template with everything folded shut is hostile; the folds
    -- are there for when they're wanted.
    vim.opt_local.foldlevel = 99
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('ejs_fold', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'ejs',
    desc = 'ejs.nvim: fold <% %> control-flow blocks',
    callback = function(args)
      M.attach(args.buf)
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'ejs' then
      M.attach(bufnr)
    end
  end

  vim.api.nvim_create_autocmd('BufDelete', {
    group = group,
    callback = function(args)
      cache[args.buf] = nil
    end,
  })
end

return M
