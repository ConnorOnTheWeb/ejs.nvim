local M = {}

function M.setup()
  -- Tell Neovim that .ejs files should use the embedded_template parser.
  -- The parser name is 'embedded_template' (from tree-sitter-embedded-template);
  -- 'ejs' is only the filetype alias.
  vim.treesitter.language.register('embedded_template', 'ejs')
end

return M
