-- Buffer-local options for EJS files.
--
-- `commentstring` is the base for `gc`. Neovim resolves the comment string
-- from the deepest Tree-sitter tree containing the cursor, so inside an
-- injected region `gc` already does the right thing on its own — `<!-- -->`
-- in markup, `//` inside a `<% %>` block. This value is what's used on the
-- delimiters themselves and anywhere no injection applies.
vim.bo.commentstring = '<%# %s %>'

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
