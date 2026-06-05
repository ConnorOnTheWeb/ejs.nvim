local M = {}

function M.setup()
  -- If nvim-treesitter is managed by lazy.nvim, it may not yet be loaded when
  -- this runs (ejs.nvim loads on FileType ejs, nvim-treesitter may load later).
  -- nvim-treesitter's runtime/ directory must be in runtimepath before the
  -- embedded_template parser starts processing the buffer, because the CSS
  -- injection chain depends on html_tags/injections.scm which lives there.
  -- Forcing it to load here ensures that directory is available in time.
  pcall(function()
    require('lazy').load({ plugins = { 'nvim-treesitter' } })
  end)

  -- Tell Neovim that .ejs files should use the embedded_template parser.
  -- The parser name is 'embedded_template' (from tree-sitter-embedded-template);
  -- 'ejs' is only the filetype alias.
  vim.treesitter.language.register('embedded_template', 'ejs')
end

return M
