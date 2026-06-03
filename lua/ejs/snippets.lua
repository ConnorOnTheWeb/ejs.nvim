local M = {}

function M.setup()
  local ok, ls = pcall(require, 'luasnip')
  if not ok then
    return
  end

  local s = ls.snippet
  local t = ls.text_node
  local i = ls.insert_node

  ls.add_snippets('ejs', {

    -- <%=  Escaped output tag
    -- Expands to: <%= expression %>
    s(
      { trig = '<%=', name = 'EJS escaped output', dscr = 'Insert a <%= %> escaped output tag', wordTrig = false },
      { t('<%= '), i(1, 'expression'), t(' %>') }
    ),

    -- <%-  Unescaped output tag
    -- Expands to: <%- expression %>
    s(
      { trig = '<%-', name = 'EJS unescaped output', dscr = 'Insert a <%- %> unescaped output tag', wordTrig = false },
      { t('<%- '), i(1, 'expression'), t(' %>') }
    ),

    -- <%  Scriptlet block
    -- Expands to: <% code %>
    s(
      { trig = '<%', name = 'EJS scriptlet', dscr = 'Insert a <% %> scriptlet tag', wordTrig = false },
      { t('<% '), i(1, 'code'), t(' %>') }
    ),

    -- <%#  Comment tag
    -- Expands to: <%# comment %>
    s(
      { trig = '<%#', name = 'EJS comment', dscr = 'Insert a <%# %> comment tag', wordTrig = false },
      { t('<%# '), i(1, 'comment'), t(' %>') }
    ),

    -- ejsinclude  Partial include
    -- Expands to: <%- include('path/to/partial', { key: value }) %>
    s(
      { trig = 'ejsinclude', name = 'EJS include partial', dscr = "Insert a <%- include() %> partial tag" },
      { t("<%- include('"), i(1, 'path/to/partial'), t("', { "), i(2), t(' }) %>') }
    ),

    -- ejsfor  forEach loop over an array
    -- Expands to a forEach block wrapping template content
    s(
      { trig = 'ejsfor', name = 'EJS forEach loop', dscr = 'Insert a forEach loop block' },
      {
        t('<% '), i(1, 'items'), t('.forEach(function('), i(2, 'item'), t(') { %>'),
        t({ '', '  ' }), i(3, '<!-- loop content -->'),
        t({ '', '<% }); %>' }),
      }
    ),

    -- ejsif  if / else block
    -- Expands to an if/else conditional block
    s(
      { trig = 'ejsif', name = 'EJS if/else block', dscr = 'Insert an if/else conditional block' },
      {
        t('<% if ('), i(1, 'condition'), t(') { %>'),
        t({ '', '  ' }), i(2, '<!-- truthy content -->'),
        t({ '', '<% } else { %>' }),
        t({ '', '  ' }), i(3, '<!-- falsy content -->'),
        t({ '', '<% } %>' }),
      }
    ),

    -- ejspage  Full EJS page scaffold
    -- Expands to a complete HTML5 document with EJS-friendly structure
    s(
      { trig = 'ejspage', name = 'EJS page scaffold', dscr = 'Insert a full HTML5 EJS page template' },
      {
        t('<!DOCTYPE html>'),
        t({ '', '<html lang="' }), i(1, 'en'), t('">'),
        t({ '', '  <head>' }),
        t({ '', '    <meta charset="UTF-8" />' }),
        t({ '', '    <meta name="viewport" content="width=device-width, initial-scale=1.0" />' }),
        t({ '', '    <title>' }), i(2, 'Page Title'), t('</title>'),
        t({ '', '  </head>' }),
        t({ '', '  <body>' }),
        t({ '', '    ' }), i(3, '<!-- content -->'),
        t({ '', '  </body>' }),
        t({ '', '</html>' }),
      }
    ),
  })
end

return M
