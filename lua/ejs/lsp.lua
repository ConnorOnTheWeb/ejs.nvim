local M = {}

--- Returns true when the cursor is inside a Tree-sitter (code) node,
--- meaning it is inside a <% %> EJS tag. Returns false for (content) nodes
--- (plain HTML) and when no parser is active.
local function cursor_in_code_node()
  local node = vim.treesitter.get_node()
  if not node then
    return false
  end
  local n = node
  while n do
    if n:type() == 'code' then
      return true
    end
    n = n:parent()
  end
  return false
end

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
    vim.lsp.start({
      name = 'ts_ls',
      cmd = { 'typescript-language-server', '--stdio' },
      root_dir = root_dir,
      on_attach = function(client, attached_bufnr)
        -- The root problem: Neovim sends textDocument/documentHighlight to all
        -- attached clients on CursorHold. ts_ls only understands JS content, so
        -- when the cursor is on an HTML (content) node it returns -32603.
        --
        -- Fix: tell Neovim that this ts_ls instance does not provide
        -- documentHighlight (prevents the automatic dispatch), then manually
        -- drive the request from a CursorHold autocmd, routing to ts_ls only
        -- when the cursor is confirmed to be inside a (code) node.
        client.server_capabilities.documentHighlightProvider = false

        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
          buffer = attached_bufnr,
          desc = 'ejs.nvim: send documentHighlight to ts_ls only for JS nodes',
          callback = function()
            if not cursor_in_code_node() then
              -- Cursor is in HTML content; clear any stale JS highlights and stop.
              vim.lsp.util.buf_clear_references(attached_bufnr)
              return
            end
            local win = vim.api.nvim_get_current_win()
            local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
            client.request(
              'textDocument/documentHighlight',
              params,
              function(err, result)
                if err or not result then
                  vim.lsp.util.buf_clear_references(attached_bufnr)
                  return
                end
                vim.lsp.util.buf_highlight_references(attached_bufnr, result, client.offset_encoding)
              end,
              attached_bufnr
            )
          end,
        })
      end,
    }, { bufnr = bufnr })
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
