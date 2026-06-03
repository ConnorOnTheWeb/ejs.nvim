local M = {}

--- Attach LSP clients to a single EJS buffer.
--- Guards against duplicate client attachment on the same buffer.
---@param bufnr integer
local function attach(bufnr)
  local root_dir = vim.fs.root(bufnr, { 'package.json', '.git' }) or vim.fn.getcwd()

  -- html-lsp (vscode-html-language-server) covers the HTML portions.
  if
    vim.fn.executable('vscode-html-language-server') == 1
    and #vim.lsp.get_clients({ bufnr = bufnr, name = 'html' }) == 0
  then
    vim.lsp.start(
      { name = 'html', cmd = { 'vscode-html-language-server', '--stdio' }, root_dir = root_dir },
      { bufnr = bufnr }
    )
  end

  -- ts_ls (typescript-language-server) covers the JavaScript portions.
  -- 'ts_ls' is the correct name as of nvim-lspconfig v2+ (September 2024).
  -- Do NOT use the deprecated name 'tsserver'.
  if
    vim.fn.executable('typescript-language-server') == 1
    and #vim.lsp.get_clients({ bufnr = bufnr, name = 'ts_ls' }) == 0
  then
    vim.lsp.start(
      { name = 'ts_ls', cmd = { 'typescript-language-server', '--stdio' }, root_dir = root_dir },
      { bufnr = bufnr }
    )
  end
end

function M.setup()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'ejs',
    desc = 'ejs.nvim: attach LSP clients to EJS buffers',
    callback = function(args)
      attach(args.buf)
    end,
  })

  -- Handle buffers that are already open with filetype=ejs.
  -- This covers the case where setup() is called after FileType has already
  -- fired for the current buffer (e.g. triggered from plugin/ejs.lua's once autocmd).
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'ejs' then
      attach(bufnr)
    end
  end
end

return M
