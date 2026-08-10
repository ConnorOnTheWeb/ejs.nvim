-- Resolution for EJS `include()` paths, shared by completion, `gf`,
-- go-to-definition and the missing-include diagnostic.
--
-- Two conventions have to work, because both are in common use and EJS itself
-- supports both:
--
--   include('partials/head')   relative to the including file's directory,
--                              which is what EJS does by default and what
--                              ejs-colorizer's includeResolver.ts implements
--   include('partials/head')   relative to the Express `views` root, for
--                              projects that render from a shared root
--
-- File-relative is tried first (it is EJS's own runtime behaviour), then the
-- views root. When a file sits at the views root the two agree, which is the
-- common case; when they disagree, the file that actually exists wins.
local M = {}

--- Matches `include('path')` / `include("path", { ... })`, capturing the quote
--- and the path. EJS also allows `include path` in v1 syntax, which v2+
--- removed; only the function form is recognised.
M.INCLUDE_PATTERN = "include%s*%(%s*(['\"])([^'\"]*)%1"

local EXTENSIONS = { '.ejs', '.html', '.htm' }

local function is_file(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == 'file'
end

local function is_directory(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == 'directory'
end

--- Project root, used as the base for the `views` lookup.
---@param bufnr integer
---@return string
function M.project_root(bufnr)
  local ok, root = pcall(vim.fs.root, bufnr, { 'package.json', '.git' })
  if ok and root then
    return root
  end
  return vim.fn.getcwd()
end

--- The Express views root for a buffer, or nil when there isn't one.
---
--- Prefers the nearest ancestor directory literally named `views` (so a file
--- at `views/pages/home.ejs` resolves `partials/head` against `views/`), and
--- falls back to `<project root>/views`.
---@param bufnr integer
---@return string?
function M.views_root(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file ~= '' then
    local dir = vim.fs.dirname(file)
    while dir and dir ~= '/' and dir ~= '.' do
      if vim.fs.basename(dir) == 'views' then
        return dir
      end
      local parent = vim.fs.dirname(dir)
      if parent == dir then
        break
      end
      dir = parent
    end
  end

  local candidate = M.project_root(bufnr) .. '/views'
  if is_directory(candidate) then
    return candidate
  end
  return nil
end

--- Every directory an include path may be resolved against, in priority order.
---@param bufnr integer
---@return string[]
function M.search_roots(bufnr)
  local roots = {}
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file ~= '' then
    table.insert(roots, vim.fs.dirname(file))
  end
  local views = M.views_root(bufnr)
  if views and views ~= roots[1] then
    table.insert(roots, views)
  end
  return roots
end

--- Resolves a raw include path to a file on disk.
---@param raw string The path as written inside the quotes
---@param bufnr integer
---@return string? path Absolute path, nil when nothing matches
---@return string? tried The first candidate, for reporting a missing include
function M.resolve(raw, bufnr)
  if raw == '' then
    return nil, nil
  end

  local roots = M.search_roots(bufnr)
  local first_candidate = nil

  -- An absolute include path is resolved against the views root, matching
  -- EJS's own behaviour when a `root` option is configured.
  if raw:sub(1, 1) == '/' then
    local views = M.views_root(bufnr)
    roots = views and { views } or {}
    raw = raw:sub(2)
  end

  for _, root in ipairs(roots) do
    local base = root .. '/' .. raw
    first_candidate = first_candidate or (vim.fn.fnamemodify(base, ':e') ~= '' and base or base .. '.ejs')

    if vim.fn.fnamemodify(base, ':e') ~= '' and is_file(base) then
      return vim.fs.normalize(base), first_candidate
    end
    for _, extension in ipairs(EXTENSIONS) do
      if is_file(base .. extension) then
        return vim.fs.normalize(base .. extension), first_candidate
      end
    end
    -- `include('partials')` may point at `partials/index.ejs`.
    if is_directory(base) and is_file(base .. '/index.ejs') then
      return vim.fs.normalize(base .. '/index.ejs'), first_candidate
    end
  end

  return nil, first_candidate
end

--- Completion candidates for a partially typed include path.
---
--- `prefix` is the text between the opening quote and the cursor, so
--- `partials/he` lists the contents of `partials/` filtered by the engine.
---@param prefix string
---@param bufnr integer
---@return table[] entries { name, path, is_directory }
function M.candidates(prefix, bufnr)
  local directory_part = prefix:match('^(.*/)') or ''
  local entries, seen = {}, {}

  for _, root in ipairs(M.search_roots(bufnr)) do
    local directory = vim.fs.normalize(root .. '/' .. directory_part)
    local handle = vim.uv.fs_scandir(directory)
    if handle then
      while true do
        local name, kind = vim.uv.fs_scandir_next(handle)
        if not name then
          break
        end
        if name:sub(1, 1) ~= '.' and not seen[directory_part .. name] then
          if kind == 'directory' then
            seen[directory_part .. name] = true
            table.insert(entries, {
              name = directory_part .. name .. '/',
              path = directory .. '/' .. name,
              is_directory = true,
            })
          elseif kind == 'file' then
            local extension = name:match('%.([%w]+)$')
            if extension and (extension == 'ejs' or extension == 'html' or extension == 'htm') then
              seen[directory_part .. name] = true
              -- EJS resolves a missing extension itself, so offer the path
              -- without `.ejs` — the form that appears in real templates.
              local label = extension == 'ejs' and name:sub(1, -5) or name
              table.insert(entries, {
                name = directory_part .. label,
                path = directory .. '/' .. name,
                is_directory = false,
              })
            end
          end
        end
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.is_directory ~= b.is_directory then
      return a.is_directory
    end
    return a.name < b.name
  end)
  return entries
end

--- Every `include()` call in a buffer, with byte positions of the path.
---@param bufnr integer
---@return table[] includes { raw, lnum (0-indexed), col, end_col }
function M.find_includes(bufnr)
  local includes = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local from = 1
    while true do
      local s, e, _, raw = line:find(M.INCLUDE_PATTERN, from)
      if not s then
        break
      end
      -- Position of the path text itself, inside the quotes.
      local quote_at = line:find('[\'"]', s)
      table.insert(includes, {
        raw = raw,
        lnum = lnum - 1,
        col = quote_at,
        end_col = quote_at + #raw,
      })
      from = e + 1
    end
  end
  return includes
end

--- `includeexpr` implementation, so plain `gf` opens an include path.
---@param fname string
---@return string
function M.gf(fname)
  local resolved = M.resolve(fname, vim.api.nvim_get_current_buf())
  return resolved or fname
end

--- Jumps to the file referenced by the `include()` under the cursor.
---@return boolean handled
function M.goto_definition()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum, col = cursor[1] - 1, cursor[2] + 1

  for _, include in ipairs(M.find_includes(bufnr)) do
    if include.lnum == lnum and col >= include.col and col <= include.end_col then
      local resolved = M.resolve(include.raw, bufnr)
      if not resolved then
        vim.notify("ejs.nvim: no file found for include('" .. include.raw .. "')", vim.log.levels.WARN)
        return true
      end
      vim.cmd('edit ' .. vim.fn.fnameescape(resolved))
      return true
    end
  end

  return false
end

return M
