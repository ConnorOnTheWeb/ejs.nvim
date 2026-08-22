-- The EJS comment toggle: five line shapes, five styles, and the round trip.
--
-- These are the shape assertions. The stronger check — compiling every result
-- with the real EJS engine across every contiguous selection — lives in
-- tests/render/ and needs node, because that methodology is the only one that
-- does not share the assumption being tested. Two of the bugs these tests now
-- guard were invisible from the output string alone.
local describe, it, eq, truthy, falsy = T.describe, T.it, T.eq, T.truthy, T.falsy

local comment = require('ejs.comment')
local region = require('ejs.region')

--- A loaded, parsed .ejs buffer.
local function buf(lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '.ejs')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = 'ejs'
  pcall(vim.treesitter.start, bufnr)
  return bufnr
end

local function shape_of(lines, lnum)
  local bufnr = buf(lines)
  local regions = region.code_regions(bufnr, { include_comments = true })
  return comment.classify(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), lnum, regions)
end

--- Toggles a range and returns the buffer's lines.
local function toggled(lines, first, last)
  local bufnr = buf(lines)
  comment.toggle(bufnr, first, last or first)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

describe('comment: line classification', function()
  it('calls plain markup markup', function()
    eq('markup', shape_of({ '<p>Hi</p>' }, 1))
  end)

  it('calls a line that is exactly one tag a whole tag', function()
    eq('whole_tag', shape_of({ '<% if (a) { %>', 'x', '<% } %>' }, 1))
    eq('whole_tag', shape_of({ '<%= x %>' }, 1))
  end)

  it('calls markup carrying a tag markup_with_tag', function()
    eq('markup_with_tag', shape_of({ '<p><%= x %></p>' }, 1))
    eq('markup_with_tag', shape_of({ '<div id="<%= x %>">y</div>' }, 1))
  end)

  it('calls a scriptlet body line code', function()
    eq('code', shape_of({ '<%', '  const a = 1;', '%>' }, 2))
  end)

  it('calls a lone delimiter a delimiter', function()
    eq('delimiter', shape_of({ '<%', '  const a = 1;', '%>' }, 1))
    eq('delimiter', shape_of({ '<%', '  const a = 1;', '%>' }, 3))
  end)

  it('does not treat the <%% literal escape as a tag', function()
    -- `<%%` renders a literal `<%`; it opens nothing.
    eq('markup', shape_of({ '<p>a <%% b</p>' }, 1))
  end)
end)

describe('comment: each shape gets its own style', function()
  it('wraps markup in <%# %>', function()
    -- Not an HTML comment: `<%#` removes the line from the output, while
    -- `<!-- -->` ships it to the browser. Those are different things.
    eq({ '<%# <p>Hi</p> %>' }, toggled({ '<p>Hi</p>' }, 1))
  end)

  it('marks a whole tag rather than wrapping it', function()
    -- Wrapping would close the comment at the tag's own %>.
    eq({ '<%#if (a) { %>', 'x', '<% } %>' }, toggled({ '<% if (a) { %>', 'x', '<% } %>' }, 1))
  end)

  it('preserves a delimiter marker when marking a tag', function()
    eq({ '<%#= x %>' }, toggled({ '<%= x %>' }, 1))
    eq({ '<%#- x %>' }, toggled({ '<%- x %>' }, 1))
  end)

  it('uses a one-line dead branch for markup carrying a tag', function()
    eq(
      { '<% if (false) { %><p><%= x %></p><% } %>' },
      toggled({ '<p><%= x %></p>' }, 1)
    )
  end)

  it('prefixes a scriptlet body line with //', function()
    eq({ '<%', '  // const a = 1;', '%>' }, toggled({ '<%', '  const a = 1;', '%>' }, 2))
  end)

  it('leaves a lone delimiter alone', function()
    -- Commenting one changes the block structure the rest of the selection
    -- was classified against, so the next toggle comments again instead of
    -- uncommenting.
    eq({ '<%', '  const a = 1;', '%>' }, toggled({ '<%', '  const a = 1;', '%>' }, 1))
  end)

  it('leaves a code line carrying the closing %> alone', function()
    eq({ '<%', '  const a = 1; %>' }, toggled({ '<%', '  const a = 1; %>' }, 2))
  end)

  it('preserves indentation', function()
    eq({ '    <%# <p>Hi</p> %>' }, toggled({ '    <p>Hi</p>' }, 1))
  end)

  it('skips blank lines rather than commenting nothing', function()
    eq({ '<%# <p>a</p> %>', '', '<%# <p>b</p> %>' }, toggled({ '<p>a</p>', '', '<p>b</p>' }, 1, 3))
  end)
end)

describe('comment: round trips', function()
  local cases = {
    { 'markup', { '<p>Hi</p>' }, 1 },
    { 'whole tag', { '<% if (a) { %>', 'x', '<% } %>' }, 1 },
    { 'output tag', { '<%= x %>' }, 1 },
    { 'unescaped tag', { '<%- x %>' }, 1 },
    { 'markup with tag', { '<p><%= x %></p>' }, 1 },
    { 'scriptlet body', { '<%', '  const a = 1;', '%>' }, 2 },
    { 'indented markup', { '    <p>Hi</p>' }, 1 },
    { 'markup with two tags', { '<p><%= a %> and <%= b %></p>' }, 1 },
  }

  for _, case in ipairs(cases) do
    local label, lines, lnum = case[1], case[2], case[3]
    it(label .. ' restores byte for byte', function()
      local bufnr = buf(lines)
      comment.toggle(bufnr, lnum, lnum)
      local commented = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      truthy(
        table.concat(commented, '\n') ~= table.concat(lines, '\n'),
        label .. ' should actually change when commented'
      )
      pcall(function()
        vim.treesitter.get_parser(bufnr, region.LANGUAGE):parse()
      end)
      comment.toggle(bufnr, lnum, lnum)
      eq(lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)
  end
end)

describe('comment: style detection', function()
  -- Commenting changes what a line classifies as — `<p>Hi</p>` is markup, and
  -- `<%# <p>Hi</p> %>` is a whole tag. Uncommenting has to go by the style
  -- that produced the line, not by its new shape.
  it('tells the wrap style from the marker style by the space', function()
    eq('markup', comment.comment_style('<%# <p>Hi</p> %>', 'whole_tag'))
    eq('whole_tag', comment.comment_style('<%#if (a) { %>', 'whole_tag'))
  end)

  it('recognises the dead branch', function()
    eq('markup_with_tag', comment.comment_style('<% if (false) { %><p>a</p><% } %>', 'markup_with_tag'))
  end)

  it('recognises a // line only inside code', function()
    eq('code', comment.comment_style('// const a = 1;', 'code'))
    eq(nil, comment.comment_style('// not code', 'markup'))
  end)

  it('reports nil for an uncommented line', function()
    eq(nil, comment.comment_style('<p>Hi</p>', 'markup'))
    eq(nil, comment.comment_style('<% if (a) { %>', 'whole_tag'))
  end)

  it('unwinds a doubled marker one level at a time', function()
    -- Commenting an already-commented whole-tag line adds a second marker
    -- rather than a second wrap, which would itself terminate early.
    eq('<%## <p>a</p> %>', comment.comment_body('<%# <p>a</p> %>', 'whole_tag'))
    eq('<%# <p>a</p> %>', comment.uncomment_body('<%## <p>a</p> %>', 'whole_tag'))
  end)
end)

describe('comment: toggling a range', function()
  it('comments a mixed selection in the right style throughout', function()
    eq({
      '<%# <p>Intro</p> %>',
      '<%#if (show) { %>',
      '<% if (false) { %><li><%= name %></li><% } %>',
      '<%#} %>',
    }, toggled({
      '<p>Intro</p>',
      '<% if (show) { %>',
      '<li><%= name %></li>',
      '<% } %>',
    }, 1, 4))
  end)

  it('uncomments only when every commentable line is commented', function()
    -- One uncommented line means the whole selection gets commented.
    eq({
      '<%## <p>a</p> %>',
      '<%# <p>b</p> %>',
    }, toggled({
      '<%# <p>a</p> %>',
      '<p>b</p>',
    }, 1, 2))
  end)
end)

describe('diagnostic settings', function()
  local config = require('ejs.config')

  it('defaults to WARN', function()
    eq(vim.diagnostic.severity.WARN, config.severity(nil))
    eq(vim.diagnostic.severity.WARN, config.severity('warn'))
  end)

  it('maps every accepted name', function()
    eq(vim.diagnostic.severity.ERROR, config.severity('error'))
    eq(vim.diagnostic.severity.INFO, config.severity('info'))
    eq(vim.diagnostic.severity.HINT, config.severity('hint'))
    eq(vim.diagnostic.severity.WARN, config.severity('warning'))
  end)

  it('treats off and false as switched off', function()
    eq(nil, config.severity('off'))
    eq(nil, config.severity(false))
  end)

  it('falls back to the default rather than erroring on a typo', function()
    eq(vim.diagnostic.severity.WARN, config.severity('wrn'))
  end)

  it('keeps the pre-1.2.0 boolean spelling working', function()
    eq(
      { missing_include = 'off', broken_comment = 'off' },
      config.normalize({ diagnostics = false }).diagnostics
    )
    eq(
      { missing_include = 'warn', broken_comment = 'warn' },
      config.normalize({ diagnostics = true }).diagnostics
    )
    falsy(config.diagnostics_enabled({ missing_include = 'off', broken_comment = 'off' }))
    truthy(config.diagnostics_enabled({ missing_include = 'off', broken_comment = 'warn' }))
    falsy(config.diagnostics_enabled(false))
    truthy(config.diagnostics_enabled(nil))
  end)
end)
