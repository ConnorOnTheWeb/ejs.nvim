# ejs.nvim

First-class EJS (Embedded JavaScript) template support for Neovim. Wires up
the existing `tree-sitter-embedded-template` grammar with language injection,
LSP configuration, and LuaSnip snippets. Works out of the box with lazy.nvim.

## Features

- Tree-sitter syntax highlighting: HTML outside `<% %>` tags, JavaScript inside them
- Language injection via `queries/ejs/injections.scm` using the `embedded_template` parser
- LSP attachment: `html-lsp` for HTML portions, `ts_ls` for JavaScript portions
- LuaSnip snippets for common EJS patterns
- `:checkhealth ejs` to verify your setup
- Zero manual config required beyond installation

## Prerequisites

All dependencies are optional. The plugin degrades gracefully when any of them
are absent.

| Dependency | Purpose | Required |
|---|---|---|
| Neovim >= 0.10 | `vim.fs.root()` API | Yes |
| `nvim-treesitter/nvim-treesitter` | Parser management and highlighting | Recommended |
| `html-lsp` (`vscode-html-language-server`) | HTML language server | Optional |
| `typescript-language-server` | JavaScript/TypeScript language server | Optional |
| `L3MON4D3/LuaSnip` | Snippet engine | Optional |

Install `html-lsp` and `typescript-language-server` via npm if you want LSP support:

```sh
npm install -g vscode-langservers-extracted typescript typescript-language-server
```

## Installation

### lazy.nvim

```lua
{
  "connorontheweb/ejs.nvim",
  ft = "ejs",
  dependencies = {
    "nvim-treesitter/nvim-treesitter", -- optional, recommended
    "neovim/nvim-lspconfig",           -- optional
    "L3MON4D3/LuaSnip",               -- optional
  },
  opts = {},
}
```

### Post-install: install the Tree-sitter parser

After installing the plugin, run the following command inside Neovim to install
the `embedded_template` Tree-sitter parser:

```
:TSInstall embedded_template
```

This only needs to be done once.

## Configuration

All options default to `true`. Pass a table to `opts` (lazy.nvim) or
`require('ejs').setup()` to override:

```lua
require('ejs').setup({
  treesitter = true,  -- register the embedded_template parser for .ejs files
  lsp        = true,  -- attach html-lsp and ts_ls on FileType ejs
  snippets   = true,  -- load LuaSnip snippets (silently skipped if LuaSnip absent)
})
```

## Health checks

Run `:checkhealth ejs` to diagnose your setup. The following checks are performed:

| Check | Pass condition | Failure level |
|---|---|---|
| Neovim version | >= 0.10 | Error |
| `embedded_template` parser | Installed via `:TSInstall` | Error |
| `vscode-html-language-server` | Found on `$PATH` | Warning |
| `typescript-language-server` | Found on `$PATH` | Warning |
| LuaSnip | Installed and loadable | Warning |

Warnings mean the corresponding feature is unavailable but the rest of the
plugin still works. Errors indicate that a required component is missing.

## Snippets reference

Snippets are registered for the `ejs` filetype and are available immediately
after opening a `.ejs` file (assuming LuaSnip is installed).

| Trigger | Expands to |
|---|---|
| `<%=` | `<%= expression %>` |
| `<%-` | `<%- expression %>` |
| `<%` | `<% code %>` |
| `<%#` | `<%# comment %>` |
| `ejsinclude` | `<%- include('path/to/partial', { }) %>` |
| `ejsfor` | `<% items.forEach(function(item) { %>`...`<% }); %>` |
| `ejsif` | `<% if (condition) { %>`...`<% } else { %>`...`<% } %>` |
| `ejspage` | Full HTML5 document scaffold with `<html>`, `<head>`, `<body>` |

All snippet triggers use tab stops so you can jump between the editable fields
with your LuaSnip jump key (typically `<Tab>`).

## How it works

### Filetype detection

`ftdetect/ejs.lua` calls `vim.filetype.add({ extension = { ejs = 'ejs' } })`,
which registers the `ejs` filetype for all `.ejs` files at startup.

### Tree-sitter

`lua/ejs/treesitter.lua` calls:

```lua
vim.treesitter.language.register('embedded_template', 'ejs')
```

This tells Neovim to use the `embedded_template` parser (from
`tree-sitter/tree-sitter-embedded-template`) whenever a buffer with filetype
`ejs` is opened.

`queries/ejs/injections.scm` injects:
- `html` into `(content)` nodes (text outside `<% %>` tags)
- `javascript` into `(code)` nodes (text inside `<% %>` tags)

Both injections use `#set! injection.combined` so that multiple disjoint
regions of the same language are merged into a single virtual document for
consistent highlighting and LSP coverage.

### LSP

`lua/ejs/lsp.lua` registers a `FileType ejs` autocommand that calls
`vim.lsp.start()` for `html` and `ts_ls`. Before starting each client, it
checks `vim.lsp.get_clients()` to prevent duplicate attachment. The binary
names `vscode-html-language-server` and `typescript-language-server` must be
on `$PATH`.

`ts_ls` is attached with an `on_attach` callback that disables the
`documentHighlightProvider` capability for the client. Without this, Neovim
sends `textDocument/documentHighlight` to `ts_ls` whenever the cursor rests on
an HTML node, which the server cannot handle and returns a `-32603` error. A
buffer-local `CursorHold` autocmd replaces the default dispatch: it uses
`vim.treesitter.get_node()` to check whether the cursor is inside a `(code)`
node and only sends the request to `ts_ls` when it is. Stale highlights are
cleared when the cursor moves back into HTML content.

`root_dir` is resolved with:

```lua
vim.fs.root(bufnr, { 'package.json', '.git' }) or vim.fn.getcwd()
```

### Snippets

`lua/ejs/snippets.lua` is wrapped in `pcall(require, 'luasnip')` and returns
silently if LuaSnip is not installed. No errors are raised.

## License

MIT. See [LICENSE](LICENSE).
