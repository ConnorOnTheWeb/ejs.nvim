# ejs.nvim

First-class EJS (Embedded JavaScript) template support for Neovim. Wires up
the existing `tree-sitter-embedded-template` grammar with language injection,
LSP configuration, and LuaSnip snippets.

## Features

- Tree-sitter syntax highlighting: HTML outside `<% %>` tags, JavaScript inside them
- Language injection via `queries/embedded_template/injections.scm` using the `embedded_template` parser
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

### No plugin manager (built-in packages)

Neovim has built-in package support. The `pack` directory may not exist yet;
create it and clone in one step:

```sh
mkdir -p ~/.local/share/nvim/site/pack/plugins/start
git clone https://github.com/connorontheweb/ejs.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/ejs.nvim
```

`~/.local/share/nvim` is the default data directory on macOS and Linux. On
Windows it is `~/AppData/Local/nvim-data`. To find the exact path on any OS,
run this inside Neovim: `:lua print(vim.fn.stdpath('data'))`

The `plugins` part of the path is an arbitrary namespace you can change to
anything. `start` means the plugin loads automatically on startup.

Then add this to your `init.lua`:

```lua
require('ejs').setup()
```

If you use `init.vim` instead:

```vim
lua require('ejs').setup()
```

### vim-plug

```vim
Plug 'connorontheweb/ejs.nvim'
```

Then in your config:

```lua
require('ejs').setup()
```

### packer.nvim

```lua
use 'connorontheweb/ejs.nvim'
```

### mini.deps

```lua
MiniDeps.add('connorontheweb/ejs.nvim')
require('ejs').setup()
```

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

When using lazy.nvim with `opts = {}`, `setup()` is called automatically by
lazy.nvim. For all other setups, call `require('ejs').setup()` explicitly in
your config. `setup()` is idempotent and safe to call multiple times.

### Post-install: install the Tree-sitter parser

After installing the plugin, install the required Tree-sitter parsers inside
Neovim:

```
:TSInstall embedded_template html css
```

`embedded_template` parses the EJS structure. `html` handles the HTML content
between EJS tags. `css` handles CSS inside `<style>` blocks, injected
automatically via the HTML parser's own injection queries. All three only need
to be installed once.

## Configuration

All options default to `true`. Pass overrides to `require('ejs').setup()`, or
via `opts` if using lazy.nvim:

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
| `html` parser | Installed via `:TSInstall` | Warning |
| `css` parser | Installed via `:TSInstall` | Warning |
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

`queries/embedded_template/injections.scm` injects:
- `html` into `(content)` nodes (text outside `<% %>` tags)
- `javascript` into `(code)` nodes that are children of `(directive)` nodes (`<% %>` scriptlet blocks)
- `javascript` into `(code)` nodes that are children of `(output_directive)` nodes (`<%= %>` and `<%- %>` output blocks)

The HTML injection uses `#set! injection.combined` so that all `(content)`
fragments are merged into a single virtual HTML document for consistent
highlighting. The JavaScript injections do not use `injection.combined` --
each `(code)` block is parsed independently, because concatenating disconnected
scriptlet blocks rarely produces valid JavaScript and would cause the parser to
return an error tree with no highlights.

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
