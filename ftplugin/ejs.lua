-- Buffer-local options for EJS files.
--
-- `commentstring` is only a fallback here. `gc` and `gcc` are overridden per
-- buffer by lua/ejs/comment.lua, because a single comment string cannot be
-- right for the five line shapes an EJS template is made of and this one was
-- wrong on four of them.
--
-- The dead branch is the fallback because it is strictly safer than `<%# %s %>`
-- for anything that bypasses those mappings: it compiles on any markup
-- selection whether or not there is a tag in it, where `<%#` compiled only
-- when there was not — a line like `<p><%= x %></p>` wrapped in `<%#` throws
-- `Could not find matching close tag for "<%#"` under EJS 6.
--
-- Measured, not assumed. Do not "fix" this back to `<%# %s %>`.
vim.bo.commentstring = '<% if (false) { %>%s<% } %>'

-- `gf` on an include path. EJS resolves a missing extension itself, so
-- `include('partials/head')` has to grow one before it names a file, and the
-- views root has to be searched as well as the current directory — which is
-- what includeexpr does here (see lua/ejs/include.lua).
vim.bo.suffixesadd = '.ejs,.html,.htm'
vim.bo.includeexpr = "v:lua.require'ejs.include'.gf(v:fname)"

local views = require('ejs.include').views_root(vim.api.nvim_get_current_buf())
if views then
  vim.opt_local.path:append(views)
end

vim.b.undo_ftplugin = table.concat({
  vim.b.undo_ftplugin or '',
  'setlocal commentstring< suffixesadd< includeexpr< path<',
}, ' | ')
