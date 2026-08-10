local describe, it, eq, truthy, falsy = T.describe, T.it, T.eq, T.truthy, T.falsy

local completion = require('ejs.completion')
local include = require('ejs.include')
local diagnostics = require('ejs.diagnostics')
local fold = require('ejs.fold')

--- Builds a throwaway project:
---   <tmp>/package.json
---   <tmp>/views/index.ejs
---   <tmp>/views/partials/head.ejs
---   <tmp>/views/partials/nav.html
local function fixture()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/views/partials', 'p')
  -- On macOS the temp directory is reached through a symlink (/var ->
  -- /private/var) and buffer names come back resolved, so compare against the
  -- resolved path or every assertion below fails on the prefix alone.
  dir = vim.uv.fs_realpath(dir) or dir
  vim.fn.writefile({ '{}' }, dir .. '/package.json')
  vim.fn.writefile({ '<h1>home</h1>' }, dir .. '/views/index.ejs')
  vim.fn.writefile({ '<title>t</title>' }, dir .. '/views/partials/head.ejs')
  vim.fn.writefile({ '<nav></nav>' }, dir .. '/views/partials/nav.html')
  return dir
end

--- Opens `path` in the current window with `lines` as its contents.
local function open(path, lines)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].filetype = 'ejs'
  if lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  return bufnr
end

describe('completion context', function()
  it('detects an opening tag delimiter', function()
    local ctx = completion.get_context('  <%')
    truthy(ctx)
    eq('tag', ctx.kind)
    eq('<%', ctx.keyword)
    eq(2, ctx.start_col)
  end)

  it('detects the output tag variants', function()
    eq('<%=', completion.get_context('<%=').keyword)
    eq('<%-', completion.get_context('<%-').keyword)
    eq('<%#', completion.get_context('<%#').keyword)
  end)

  it('offers every tag delimiter including the v6 literal escape', function()
    local ctx = completion.get_context('<%')
    local labels = vim.tbl_map(function(item)
      return item.label
    end, completion.items(ctx, vim.api.nvim_get_current_buf()))
    truthy(vim.tbl_contains(labels, '<%%'), '<%% literal escape is missing')
    truthy(vim.tbl_contains(labels, '<%='))
  end)

  it('detects a bare word as a scaffold position', function()
    local ctx = completion.get_context('  ejsi')
    truthy(ctx)
    eq('keyword', ctx.kind)
    eq('ejsi', ctx.keyword)
  end)

  it('detects an include path being typed', function()
    local ctx = completion.get_context("<%- include('partials/he")
    truthy(ctx)
    eq('include', ctx.kind)
    eq('he', ctx.keyword, 'only the segment after the last slash is replaced')
    eq('partials/he', ctx.prefix)
  end)

  it('detects an empty include path', function()
    local ctx = completion.get_context("<%- include('")
    truthy(ctx)
    eq('include', ctx.kind)
    eq('', ctx.keyword)
  end)

  it('ignores an ordinary string that is not an include argument', function()
    falsy(completion.get_context("<% const s = 'partials/he"))
  end)
end)

describe('include resolution', function()
  it('resolves a path relative to the including file', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs')
    eq(vim.fs.normalize(dir .. '/views/partials/head.ejs'), include.resolve('partials/head', bufnr))
  end)

  it('adds the .ejs extension when the path has none', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs')
    truthy(include.resolve('partials/head', bufnr):match('%.ejs$'))
  end)

  it('resolves an .html partial too', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs')
    truthy(include.resolve('partials/nav', bufnr))
  end)

  it('falls back to the views root from a nested file', function()
    local dir = fixture()
    vim.fn.mkdir(dir .. '/views/pages', 'p')
    vim.fn.writefile({ 'x' }, dir .. '/views/pages/about.ejs')
    local bufnr = open(dir .. '/views/pages/about.ejs')
    -- Not relative to views/pages/, only to the views root.
    eq(vim.fs.normalize(dir .. '/views/partials/head.ejs'), include.resolve('partials/head', bufnr))
  end)

  it('finds the views root by walking up from the file', function()
    local dir = fixture()
    vim.fn.mkdir(dir .. '/views/pages', 'p')
    vim.fn.writefile({ 'x' }, dir .. '/views/pages/about.ejs')
    local bufnr = open(dir .. '/views/pages/about.ejs')
    eq(vim.fs.normalize(dir .. '/views'), vim.fs.normalize(include.views_root(bufnr)))
  end)

  it('returns nil for a path that does not exist', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs')
    falsy(include.resolve('partials/missing', bufnr))
  end)

  it('lists candidates for a directory prefix', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs')
    local names = vim.tbl_map(function(entry)
      return entry.name
    end, include.candidates('partials/', bufnr))
    truthy(vim.tbl_contains(names, 'partials/head'), 'head.ejs should be offered without its extension')
    truthy(vim.tbl_contains(names, 'partials/nav.html'))
  end)

  it('lists directories with a trailing slash', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs')
    local entries = include.candidates('', bufnr)
    local partials
    for _, entry in ipairs(entries) do
      if entry.name == 'partials/' then
        partials = entry
      end
    end
    truthy(partials, 'the partials/ directory should be offered')
    truthy(partials.is_directory)
  end)

  it('finds include() calls with their positions', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs', {
      "<%- include('partials/head') %>",
      '<p>x</p>',
      '<%- include("partials/nav", { active: true }) %>',
    })
    local found = include.find_includes(bufnr)
    eq(2, #found)
    eq('partials/head', found[1].raw)
    eq(0, found[1].lnum)
    eq('partials/nav', found[2].raw)
    eq(2, found[2].lnum)
  end)
end)

describe('diagnostics', function()
  it('reports an include path that does not resolve', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs', { "<%- include('partials/nope') %>" })
    local found = diagnostics.collect(bufnr)
    eq(1, #found)
    truthy(found[1].message:find('nope', 1, true))
  end)

  it('stays quiet for an include that resolves', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs', { "<%- include('partials/head') %>" })
    eq({}, diagnostics.collect(bufnr))
  end)

  it('reports a comment closed early by a tag inside it', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs', { '<%# <%= value %> %>' })
    local found = diagnostics.collect(bufnr)
    eq(1, #found)
    truthy(found[1].message:find('ends early', 1, true))
  end)

  it('stays quiet for an ordinary comment', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs', { '<%# just a note %>' })
    eq({}, diagnostics.collect(bufnr))
  end)
end)

describe('hover', function()
  local hover = require('ejs.hover')

  --- Places the cursor at 0-indexed `col` on a one-line EJS buffer.
  local function at(line, col)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
    vim.bo[bufnr].filetype = 'ejs'
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, col })
  end

  it('documents the escaped output tag', function()
    at('<%= user.name %>', 1)
    local entry = hover.resolve()
    truthy(entry)
    eq('<%=', entry.label)
    truthy(entry.desc:lower():find('escap', 1, true))
  end)

  it('distinguishes unescaped output from escaped', function()
    at('<%- raw %>', 1)
    eq('<%-', hover.resolve().label)
  end)

  it('prefers the longest matching delimiter', function()
    -- `<%#` must not be read as `<%` with a stray `#`.
    at('<%# note %>', 1)
    eq('<%#', hover.resolve().label)
    at('<%% literal', 1)
    eq('<%%', hover.resolve().label)
  end)

  it('documents the closing delimiters', function()
    at('<% x %>', 6)
    eq('%>', hover.resolve().label)
    at('<% x -%>', 6)
    eq('-%>', hover.resolve().label)
    at('<% x _%>', 6)
    eq('_%>', hover.resolve().label)
  end)

  it('answers anywhere within the delimiter, not only its first column', function()
    at('<%= x %>', 2)
    eq('<%=', hover.resolve().label)
  end)

  it('returns nothing in ordinary markup', function()
    at('<p>hello</p>', 4)
    falsy(hover.resolve())
  end)
end)

describe('folding', function()
  it('counts an opening control-flow brace', function()
    eq(1, fold.line_delta('<% if (user) { %>'))
  end)

  it('counts a closing brace', function()
    eq(-1, fold.line_delta('<% } %>'))
  end)

  it('nets out an else branch', function()
    eq(0, fold.line_delta('<% } else { %>'))
  end)

  it('ignores braces in markup outside a tag', function()
    eq(0, fold.line_delta('<style>.a { color: red }</style>'))
  end)

  it('ignores braces inside a string', function()
    eq(0, fold.line_delta('<% const s = "{" %>'))
  end)

  it('ignores the <%% literal escape', function()
    eq(0, fold.line_delta('<%% if (x) { %>'))
  end)

  it('gives the opening and closing lines the same level', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs', {
      '<% if (user) { %>',
      '  <p>hi</p>',
      '<% } %>',
      '<p>after</p>',
    })
    vim.api.nvim_win_set_buf(0, bufnr)
    eq(1, fold.foldexpr(1))
    eq(1, fold.foldexpr(2))
    eq(1, fold.foldexpr(3))
    eq(0, fold.foldexpr(4))
  end)
end)

describe('LSP item shape', function()
  it('carries an explicit textEdit covering the typed delimiter', function()
    local ctx = completion.get_context('  <%=')
    local items = completion.lsp_items(ctx, vim.api.nvim_get_current_buf(), 1)
    truthy(#items > 0)
    eq(2, items[1].textEdit.range.start.character)
    eq(5, items[1].textEdit.range['end'].character)
  end)

  it('marks snippet items with insertTextFormat 2', function()
    local ctx = completion.get_context('<%')
    local items = completion.lsp_items(ctx, vim.api.nvim_get_current_buf(), 1)
    eq(2, items[1].insertTextFormat)
  end)

  it('replaces only the last path segment for include candidates', function()
    local dir = fixture()
    local bufnr = open(dir .. '/views/index.ejs')
    local line = "<%- include('partials/he"
    local ctx = completion.get_context(line)
    local items = completion.lsp_items(ctx, bufnr, 1)
    truthy(#items > 0)
    eq(#line - 2, items[1].textEdit.range.start.character)
  end)

  it('strips snippet syntax to plain text', function()
    eq('<%=  %>', completion.strip_snippet('<%= $1 %>'))
  end)
end)
