local M = {}

function M.check()
  vim.health.start('ejs.nvim')

  -- 1. Neovim version
  if vim.fn.has('nvim-0.10') == 1 then
    vim.health.ok('Neovim >= 0.10 (current stable: 0.12.0)')
  else
    vim.health.error(
      'Neovim >= 0.10 is required',
      { 'Upgrade Neovim. vim.fs.root() is not available before 0.10.' }
    )
  end

  -- 2. embedded_template Tree-sitter parser
  local parser_ok = pcall(vim.treesitter.language.inspect, 'embedded_template')
  if parser_ok then
    vim.health.ok('embedded_template Tree-sitter parser is installed')
  else
    vim.health.error(
      'embedded_template Tree-sitter parser is not installed',
      { 'Run :TSInstall embedded_template' }
    )
  end

  -- 3. html-lsp (vscode-html-language-server)
  if vim.fn.executable('vscode-html-language-server') == 1 then
    vim.health.ok('vscode-html-language-server found on PATH (html-lsp)')
  else
    vim.health.warn(
      'vscode-html-language-server not found on PATH',
      { 'Install html-lsp: npm install -g vscode-langservers-extracted' }
    )
  end

  -- 4. typescript-language-server (backing ts_ls)
  if vim.fn.executable('typescript-language-server') == 1 then
    vim.health.ok('typescript-language-server found on PATH (ts_ls)')
  else
    vim.health.warn(
      'typescript-language-server not found on PATH',
      { 'Install: npm install -g typescript typescript-language-server' }
    )
  end

  -- 5. LuaSnip (optional, warning only)
  local luasnip_ok = pcall(require, 'luasnip')
  if luasnip_ok then
    vim.health.ok('LuaSnip is installed; EJS snippets will be loaded')
  else
    vim.health.warn(
      'LuaSnip is not installed; EJS snippets will not be available',
      { 'Install L3MON4D3/LuaSnip to enable snippet support' }
    )
  end
end

return M
