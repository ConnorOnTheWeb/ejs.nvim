-- For every contiguous line selection of each template, apply the EJS comment
-- toggle and record the result plus the round trip. Compiled by check_ejs.mjs.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.runtimepath:prepend(root)
require('ejs').setup()

local templates = {
  ['markup only'] = {
    '<h1>Title</h1>',
    '<p>Hello there</p>',
    '<span>bye</span>',
  },
  ['markup carrying tags'] = {
    '<p>Intro</p>',
    '<span><%= name %></span>',
    '<div id="<%= name %>">x</div>',
    '<footer>bye</footer>',
  },
  ['control flow'] = {
    '<ul>',
    '<% if (show) { %>',
    '  <li><%= name %></li>',
    '<% } %>',
    '</ul>',
  },
  ['scriptlet body'] = {
    '<%',
    '  const a = 1;',
    '  const b = 2;',
    '%>',
    '<p><%= a + b %></p>',
  },
  ['mixed'] = {
    '<h1><%= title %></h1>',
    '<% const n = 2; %>',
    '<p>plain</p>',
    '<%= n %>',
  },
}

local results = {}

for name, lines in pairs(templates) do
  for first = 1, #lines do
    for last = first, #lines do
      local b = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(b, vim.fn.tempname() .. '.ejs')
      vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
      vim.api.nvim_win_set_buf(0, b)
      vim.bo[b].filetype = 'ejs'
      vim.cmd('doautocmd FileType ejs')
      pcall(vim.treesitter.start, b)
      vim.wait(20)

      require('ejs.comment').toggle(b, first, last)
      local commented = vim.api.nvim_buf_get_lines(b, 0, -1, false)

      -- Re-parse against the new text before toggling back.
      pcall(function()
        vim.treesitter.get_parser(b, 'embedded_template'):parse()
      end)
      require('ejs.comment').toggle(b, first, last)
      local back = vim.api.nvim_buf_get_lines(b, 0, -1, false)

      table.insert(results, {
        template = name,
        first = first,
        last = last,
        original = table.concat(lines, '\n'),
        commented = table.concat(commented, '\n'),
        roundtrip = table.concat(back, '\n'),
      })
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
end

vim.fn.writefile({ vim.json.encode(results) }, '/tmp/toggles.json')
print(('generated %d selections'):format(#results))
