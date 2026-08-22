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

  -- 3. html Tree-sitter parser (required for HTML highlighting and CSS injection)
  local html_ts_ok = pcall(vim.treesitter.language.inspect, 'html')
  if html_ts_ok then
    vim.health.ok('html Tree-sitter parser is installed')
  else
    vim.health.warn(
      'html Tree-sitter parser is not installed; HTML and CSS highlighting will not work',
      { 'Run :TSInstall html' }
    )
  end

  -- 4. css Tree-sitter parser (required for CSS highlighting inside <style> blocks)
  local css_ts_ok = pcall(vim.treesitter.language.inspect, 'css')
  if css_ts_ok then
    vim.health.ok('css Tree-sitter parser is installed')
  else
    vim.health.warn(
      'css Tree-sitter parser is not installed; CSS inside <style> blocks will not be highlighted',
      { 'Run :TSInstall css' }
    )
  end

  -- 5. html-lsp (vscode-html-language-server)
  if vim.fn.executable('vscode-html-language-server') == 1 then
    vim.health.ok('vscode-html-language-server found on PATH (html-lsp)')
  else
    vim.health.warn(
      'vscode-html-language-server not found on PATH',
      { 'Install html-lsp: npm install -g vscode-langservers-extracted' }
    )
  end

  -- 6. typescript-language-server (backing ts_ls)
  if vim.fn.executable('typescript-language-server') == 1 then
    vim.health.ok('typescript-language-server found on PATH (ts_ls)')
  else
    vim.health.warn(
      'typescript-language-server not found on PATH',
      { 'Install: npm install -g typescript typescript-language-server' }
    )
  end

  -- 7. LuaSnip (optional, informational)
  local luasnip_ok = pcall(require, 'luasnip')
  if luasnip_ok then
    vim.health.ok('LuaSnip is installed; EJS snippets will be loaded')
  else
    vim.health.info(
      'LuaSnip is not installed. The completion source offers the same tags and scaffolds '
        .. 'on its own (completion.snippets = true), so LuaSnip is optional.'
    )
  end

  vim.health.start('ejs.nvim: completion engines')

  local config = pcall(require, 'ejs') and require('ejs').get_config() or {}
  local completion = config.completion or {}

  local cmp_ok = pcall(require, 'cmp')
  if cmp_ok and completion.cmp ~= false then
    vim.health.ok('nvim-cmp is installed; the `ejs` source is registered')
  elseif cmp_ok then
    vim.health.info('nvim-cmp is installed but completion.cmp = false')
  else
    vim.health.info('nvim-cmp is not installed')
  end

  local blink_ok, blink = pcall(require, 'blink.cmp')
  if blink_ok and completion.blink ~= false then
    if type(blink.add_source_provider) == 'function' and type(blink.add_filetype_source) == 'function' then
      vim.health.ok('blink.cmp is installed; the `ejs` source is registered for the ejs filetype')
    else
      vim.health.warn('blink.cmp is installed but is too old to register a source at runtime', {
        'Upgrade to blink.cmp >= v1.6, or add the source manually:',
        "  sources = { default = { 'ejs', ... }, providers = { ejs = { name = 'EJS', module = 'ejs.blink' } } }",
      })
    end
  elseif blink_ok then
    vim.health.info('blink.cmp is installed but completion.blink = false')
  else
    vim.health.info('blink.cmp is not installed')
  end

  if completion.omni then
    if vim.fn.has('nvim-0.12') == 1 then
      vim.health.ok("the complete-function is chained into 'complete' (FEjsCompleteFunc)")
    else
      vim.health.ok("the complete-function is set as 'omnifunc' where nothing else claimed it")
    end
  else
    vim.health.info(
      'completion.omni = false; enable it for Neovim 0.12 built-in completion, mini.completion, or coq_nvim'
    )
  end

  vim.health.start('ejs.nvim: templates')

  local cfg = require('ejs.config')
  if not cfg.diagnostics_enabled(config.diagnostics) then
    vim.health.info('include-path and comment diagnostics are disabled')
  else
    -- An explicit map rather than a reverse lookup over vim.diagnostic.severity:
    -- that table carries short aliases (E, W, I, N) alongside the long names
    -- and both directions of the mapping, so iterating it returns whichever
    -- key `pairs` happens to reach first.
    local SEVERITY_NAMES = {
      [vim.diagnostic.severity.ERROR] = 'error',
      [vim.diagnostic.severity.WARN] = 'warn',
      [vim.diagnostic.severity.INFO] = 'info',
      [vim.diagnostic.severity.HINT] = 'hint',
    }
    local function label(check)
      local level = cfg.severity(type(config.diagnostics) == 'table' and config.diagnostics[check] or config.diagnostics)
      return level and SEVERITY_NAMES[level] or 'off'
    end
    vim.health.ok(
      ('diagnostics: missing_include = %s, broken_comment = %s'):format(
        label('missing_include'),
        label('broken_comment')
      )
    )
    vim.health.info(
      'JavaScript syntax errors are left to ts_ls, which is attached to <% %> regions and reports them '
        .. 'with better positions than the extension\'s joined-program check can.'
    )
  end

  if config.comment == false then
    vim.health.info(
      'gc / gcc are left alone; commentstring is still the dead branch, which is the safer static fallback'
    )
  else
    vim.health.ok('gc / gcc comment each line in the style its shape calls for')
  end

  if config.hover == false then
    vim.health.info('tag hover is disabled; call require("ejs").hover() from your own mapping if you want it')
  else
    vim.health.ok('tag documentation is mapped to K, falling back to LSP hover elsewhere')
  end

  if config.folding == false then
    vim.health.info('control-flow folding is disabled')
  else
    vim.health.ok('control-flow folding is enabled (folds start open)')
  end

  local include = require('ejs.include')
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype == 'ejs' then
    local views = include.views_root(bufnr)
    if views then
      vim.health.ok('views root for this buffer: ' .. vim.fn.fnamemodify(views, ':~'))
    else
      vim.health.info(
        'no views root found for this buffer; include() paths resolve relative to the file only',
        { 'Put templates under a directory named "views", or keep partial paths relative to the file.' }
      )
    end
  else
    vim.health.info('open an .ejs buffer and re-run to see how include() paths resolve there')
  end
end

return M
