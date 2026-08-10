-- Engine-agnostic completion core for EJS.
--
-- Same shape as alpinejs.nvim's: everything that decides *what* to complete
-- lives here, and cmp.lua / blink.lua / omni.lua only translate. Three things
-- are offered:
--
--   tag       EJS delimiters after `<`, including the v6 `<%%` literal escape
--   keyword   block scaffolds (`ejsif`, `ejsfor`, ...) as snippet items, so
--             they work without LuaSnip and in every completion engine
--   include   file paths inside an `include('...')` call
--
-- Items carry an explicit `textEdit`: blink.cmp otherwise guesses the replaced
-- range from its own keyword matcher, in which `<`, `%` and `/` are not
-- keyword characters, and would insert in the wrong place.
local M = {}

local KIND = {
  Function = 3,
  File = 17,
  Folder = 19,
  Snippet = 15,
  Keyword = 14,
}

M.KIND = KIND

--- EJS tag delimiters. `<%%` and `%%>` are the v6 literal escapes: they emit
--- a bare `<%` / `%>` rather than opening a tag (ejs-colorizer v2.2.7).
M.tags = {
  {
    label = '<%',
    detail = 'scriptlet',
    desc = 'Control-flow scriptlet. The code runs; nothing is written to the output.',
    snippet = '<% $1 %>',
  },
  {
    label = '<%=',
    detail = 'escaped output',
    desc = 'Writes the value to the output with HTML special characters escaped.',
    snippet = '<%= $1 %>',
  },
  {
    label = '<%-',
    detail = 'unescaped output',
    desc = 'Writes the value to the output **without** escaping. Only for trusted content.',
    snippet = '<%- $1 %>',
  },
  {
    label = '<%#',
    detail = 'comment',
    desc = 'A comment. The content is not evaluated and produces no output.',
    snippet = '<%# $1 %>',
  },
  {
    label = '<%_',
    detail = 'whitespace-slurping scriptlet',
    desc = 'Like `<%`, but strips all whitespace before the tag.',
    snippet = '<%_ $1 _%>',
  },
  {
    label = '<%%',
    detail = 'literal <%',
    desc = 'Outputs a literal `<%` into the rendered HTML instead of opening a tag. '
      .. 'Use when the output itself needs those characters, e.g. a client-side '
      .. 'template inside a server-rendered EJS file. (EJS v6)',
    snippet = '<%%',
  },
}

--- Closing delimiters. Not offered as completions — nothing sensibly
--- triggers on `%` mid-tag — but hover documents them, which is where the
--- difference between `%>`, `-%>` and `_%>` actually matters.
M.close_tags = {
  {
    label = '%>',
    detail = 'close tag',
    desc = 'Closes an EJS scriptlet or output tag.',
  },
  {
    label = '-%>',
    detail = 'newline-slurp close',
    desc = 'Closes the tag and removes the **newline** immediately after it, keeping the rendered HTML compact.',
  },
  {
    label = '_%>',
    detail = 'whitespace-slurp close',
    desc = 'Closes the tag and removes all trailing whitespace after it, including the newline.',
  },
  {
    label = '%%>',
    detail = 'literal %>',
    desc = 'Outputs a literal `%>` into the rendered HTML. The counterpart to `<%%`. (EJS v6)',
  },
}

--- Block scaffolds, mirroring lua/ejs/snippets.lua so LuaSnip users and
--- everyone else get the same set.
M.scaffolds = {
  {
    label = 'ejsinclude',
    detail = 'include a partial',
    desc = 'Insert a `<%- include() %>` partial tag.',
    snippet = "<%- include('${1:path/to/partial}', { $2 }) %>",
  },
  {
    label = 'ejsfor',
    detail = 'forEach loop',
    desc = 'Insert a `forEach` loop wrapping template content.',
    snippet = '<% ${1:items}.forEach(function (${2:item}) { %>\n  $0\n<% }); %>',
  },
  {
    label = 'ejsif',
    detail = 'if / else block',
    desc = 'Insert an if/else conditional block.',
    snippet = '<% if (${1:condition}) { %>\n  $0\n<% } else { %>\n  \n<% } %>',
  },
  {
    label = 'ejspage',
    detail = 'HTML5 page scaffold',
    desc = 'Insert a complete HTML5 document.',
    snippet = table.concat({
      '<!DOCTYPE html>',
      '<html lang="${1:en}">',
      '  <head>',
      '    <meta charset="UTF-8" />',
      '    <meta name="viewport" content="width=device-width, initial-scale=1.0" />',
      '    <title>${2:Page Title}</title>',
      '  </head>',
      '  <body>',
      '    $0',
      '  </body>',
      '</html>',
    }, '\n'),
  },
}

--------------------------------------------------------------------------------
-- Context detection
--------------------------------------------------------------------------------

--- Determines what should be completed at the cursor.
---@param line_to_cursor string
---@return table? ctx { kind, keyword, start_col }
function M.get_context(line_to_cursor)
  local cursor_col = #line_to_cursor

  -- Inside an include() path string, which may itself sit inside a `<%- %>`
  -- tag; the quote is what matters, not the tag.
  local quote_start, quote = nil, nil
  local i = 1
  while i <= #line_to_cursor do
    local c = line_to_cursor:sub(i, i)
    if quote then
      if c == quote then
        quote, quote_start = nil, nil
      end
    elseif c == '"' or c == "'" then
      quote, quote_start = c, i
    end
    i = i + 1
  end

  if quote and quote_start then
    local before = line_to_cursor:sub(1, quote_start - 1)
    if before:match('include%s*%(%s*$') then
      local typed = line_to_cursor:sub(quote_start + 1)
      -- Only the segment after the last `/` is replaced, so navigating into a
      -- directory does not re-insert the part already typed.
      local segment = typed:match('([^/]*)$') or ''
      return {
        kind = 'include',
        keyword = segment,
        prefix = typed,
        start_col = cursor_col - #segment,
      }
    end
    return nil
  end

  -- An EJS tag being opened: `<`, `<%`, `<%=` ...
  local partial = line_to_cursor:match('(<%%?[=%-#_%%]?)$')
  if partial then
    return { kind = 'tag', keyword = partial, start_col = cursor_col - #partial }
  end

  -- A bare word, for the block scaffolds.
  local word = line_to_cursor:match('([%a][%w_]*)$')
  if word then
    return { kind = 'keyword', keyword = word, start_col = cursor_col - #word }
  end

  return nil
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

--- Engine-neutral items for a context.
---@param ctx table
---@param bufnr integer
---@return table[]
function M.items(ctx, bufnr)
  local items = {}

  if ctx.kind == 'tag' then
    for _, tag in ipairs(M.tags) do
      table.insert(items, {
        label = tag.label,
        kind = KIND.Snippet,
        detail = tag.detail,
        desc = tag.desc,
        snippet = tag.snippet,
      })
    end
  elseif ctx.kind == 'keyword' then
    for _, scaffold in ipairs(M.scaffolds) do
      table.insert(items, {
        label = scaffold.label,
        kind = KIND.Snippet,
        detail = scaffold.detail,
        desc = scaffold.desc,
        snippet = scaffold.snippet,
      })
    end
  elseif ctx.kind == 'include' then
    local include = require('ejs.include')
    for _, entry in ipairs(include.candidates(ctx.prefix or '', bufnr)) do
      -- The label carries the directory part so filtering matches what the
      -- user typed; only the last segment is actually replaced.
      local segment = entry.name:match('([^/]*/?)$') or entry.name
      table.insert(items, {
        label = segment,
        kind = entry.is_directory and KIND.Folder or KIND.File,
        detail = entry.is_directory and 'directory' or 'partial',
        desc = entry.path,
        -- Re-triggering after a directory is what makes navigation feel
        -- natural, the same behaviour ejs-colorizer's provider has.
        retrigger = entry.is_directory,
      })
    end
  end

  return items
end

--------------------------------------------------------------------------------
-- Engine-facing conversions
--------------------------------------------------------------------------------

local function snippets_enabled()
  local ok, ejs = pcall(require, 'ejs')
  if not ok then
    return true
  end
  local completion = (ejs.get_config() or {}).completion
  if completion == nil or completion.snippets == nil then
    return true
  end
  return completion.snippets and true or false
end

--- Converts a snippet body to the plain text it expands to with empty tabstops.
---@param body string
---@return string
function M.strip_snippet(body)
  local out = body
  out = out:gsub('%${%d+:([^}]*)}', '%1')
  out = out:gsub('%$%{%d+%}', '')
  out = out:gsub('%$%d+', '')
  out = out:gsub('\\%$', '$')
  return out
end

--- Documentation body for an item.
---@param item table
---@return string
function M.documentation(item)
  local parts = {}
  if item.detail and item.detail ~= '' then
    table.insert(parts, '```\n' .. item.detail .. '\n```')
  end
  if item.desc and item.desc ~= '' then
    table.insert(parts, item.desc)
  end
  return table.concat(parts, '\n\n')
end

--- LSP CompletionItems, ready for nvim-cmp and blink.cmp.
---@param ctx table
---@param bufnr integer
---@param row integer 1-indexed cursor line
---@return table[]
function M.lsp_items(ctx, bufnr, row)
  local use_snippets = snippets_enabled()
  local end_col = ctx.start_col + #ctx.keyword
  local items = {}

  for _, item in ipairs(M.items(ctx, bufnr)) do
    local snippet = use_snippets and item.snippet or nil
    table.insert(items, {
      label = item.label,
      kind = item.kind,
      detail = item.detail,
      documentation = { kind = 'markdown', value = M.documentation(item) },
      insertTextFormat = snippet and 2 or 1,
      textEdit = {
        range = {
          start = { line = row - 1, character = ctx.start_col },
          ['end'] = { line = row - 1, character = end_col },
        },
        newText = snippet or item.label,
      },
    })
  end

  return items
end

--- True when the buffer is one this plugin completes in.
---@param bufnr integer
---@return boolean
function M.enabled_for_buf(bufnr)
  return vim.bo[bufnr].filetype == 'ejs'
end

M.trigger_characters = { '<', '%', '=', '-', '#', '/', "'", '"' }

return M
