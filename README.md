# ejs.nvim

First-class EJS (Embedded JavaScript) template support for Neovim. Wires up
the existing `tree-sitter-embedded-template` grammar with language injection,
LSP configuration, and LuaSnip snippets.

## Features

- Tree-sitter syntax highlighting: HTML outside `<% %>` tags, JavaScript inside them
- Language injection via `queries/embedded_template/injections.scm` using the `embedded_template` parser
- LSP attachment: `html-lsp` for HTML portions, `ts_ls` for JavaScript portions
- **`include()` path completion**, resolving both file-relative and
  views-root conventions, with directory navigation
- **`gf` and `:EjsDefinition` on include paths** — `gf` on
  `include('partials/head')` opens `views/partials/head.ejs`, extension and
  all
- **Diagnostics**: `include()` paths that do not resolve to a file, and
  `<%# %>` comments that end earlier than they look like they do
- **Tag completion** for every EJS delimiter, including the v6 `<%%` literal
  escape, plus block scaffolds — in nvim-cmp, blink.cmp, or Neovim's built-in
  completion (see [Completion engines](#completion-engines))
- **Hover documentation** on `K` for the delimiter under the cursor — what
  separates `<%=` from `<%-`, and `%>` from `-%>` and `_%>` — falling through
  to your LSP hover everywhere else
- **Comment support**: `gc` / `gcc` comment each line in the style its own
  shape calls for — `<%# %>` on markup, a `#` marker on a whole tag, a
  one-line dead branch on markup carrying a tag, `//` inside a scriptlet body
  — because a flat `commentstring` is wrong on four of the five
  (see [Comments](#comments))
- **Folding** for `<% if (...) { %> … <% } %>` control-flow blocks
- LuaSnip snippets for common EJS patterns (optional — the completion source
  offers the same scaffolds without it)
- `:checkhealth ejs` to verify your setup
- Zero manual config required beyond installation

## Prerequisites

All dependencies are optional. The plugin degrades gracefully when any of them
are absent.

| Dependency | Purpose | Required |
|---|---|---|
| Neovim >= 0.10 | `vim.fs.root()` API | Yes |
| `nvim-treesitter/nvim-treesitter` | Parser management; required for CSS highlighting in `<style>` blocks | Recommended |
| `html-lsp` (`vscode-html-language-server`) | HTML language server | Optional |
| `typescript-language-server` | JavaScript/TypeScript language server | Optional |
| `hrsh7th/nvim-cmp` **or** `saghen/blink.cmp` | Completion. Neither is needed if you use Neovim 0.12's built-in completion or mini.completion — set `completion.omni = true` instead | Optional |
| `L3MON4D3/LuaSnip` | Snippet engine. Optional even for snippets: the completion source inserts the same forms itself | Optional |

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
Neovim. The `:TSInstall` command is provided by nvim-treesitter. If you do not
have nvim-treesitter, parsers must be compiled from source (see each parser's
GitHub repo). With nvim-treesitter installed:

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

  completion = {
    cmp      = true,  -- register the nvim-cmp source
    blink    = true,  -- register the blink.cmp source
    omni     = false, -- complete-function for built-in/mini.completion/coq
    snippets = true,  -- insert `<%= | %>` rather than a bare `<%=`
  },

  -- 'error' | 'warn' | 'info' | 'hint' | 'off', per check
  diagnostics = {
    missing_include = 'warn', -- include() paths that do not resolve
    broken_comment  = 'warn', -- <%# %> comments that end earlier than they look
  },

  comment = true,     -- shape-aware gc / gcc (see Comments below)
  folding = true,     -- fold <% if (...) { %> ... <% } %> blocks
  hover   = true,     -- map K, falling through to LSP hover off a delimiter
})
```

`hint` is the useful severity: it leaves the underline in the buffer while
keeping the entry out of your location list. The pre-1.2.0 spelling
`diagnostics = true | false` still works and maps to both checks on or off.

There is no setting for JavaScript syntax errors because that check is not
ported: `ts_ls` is already attached to `<% %>` regions and reports them with
better positions than the extension's joined-program heuristic can.

## Completion engines

One core (`lua/ejs/completion.lua`) decides what to complete; the adapters
beside it only translate.

| Engine | How it is wired | Notes |
|---|---|---|
| [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) | Registered automatically as the `ejs` source | Nothing to configure |
| [blink.cmp](https://github.com/saghen/blink.cmp) | Registered automatically for the `ejs` filetype | Needs blink >= v1.6; older versions need the manual `sources.providers` entry below |
| Neovim 0.12 built-in (`vim.o.autocomplete`) | `completion.omni = true` appends `FEjsCompleteFunc` to `'complete'` | Leaves `omnifunc` with html-lsp / ts_ls |
| [mini.completion](https://github.com/nvim-mini/mini.completion) | `completion.omni = true` | Uses the same complete-function |

```lua
-- blink.cmp before v1.6, with completion.blink = false
sources = {
  default = { 'lsp', 'path', 'snippets', 'buffer', 'ejs' },
  providers = { ejs = { name = 'EJS', module = 'ejs.blink' } },
}
```

## include() paths

`include('partials/head')` is resolved against the including file's own
directory first — EJS's own runtime behaviour — and then against the views
root, which is the nearest ancestor directory named `views`, or
`<project root>/views`. A path starting with `/` is resolved against the views
root only. The `.ejs`, `.html` and `.htm` extensions are all tried, and
`include('partials')` will find `partials/index.ejs`.

That resolution backs four things: completion inside the quotes, `gf`
(via `includeexpr`), `:EjsDefinition`, and the diagnostic for a path that
matches no file. `:checkhealth ejs` reports which views root, if any, was
found for the current buffer.

An `include()` call is only recognised inside an EJS tag. `include('…')`
written in prose, in body text or inside an `<!-- -->` comment is not a call,
so it produces no diagnostic and no completion — the code regions come from
the Tree-sitter parse tree (`lua/ejs/region.lua`), with a text scan for
`<% %>` spans as the fallback when the `embedded_template` parser is not
installed.

`<%# %>` comments are the one place the features deliberately disagree. An
`include()` commented out with `<%#` produces no missing-path warning, because
a warning about an include you commented out is noise you didn't ask for.
`gf`, `:EjsDefinition` and completion still work on it, because those only
answer where the cursor already is.

## Comments

`gc` and `gcc` are overridden in EJS buffers, because `commentstring` is a
single string and an EJS template is made of five distinguishable line shapes.
Only one of them takes `<%# … %>`.

| Where the line is | Style | Result |
|---|---|---|
| Markup or text | `<%# … %>` wrap | `<p>Hi</p>` → `<%# <p>Hi</p> %>` |
| One whole EJS tag | `#` marker on the tag | `<% if (a) { %>` → `<%#if (a) { %>` |
| Markup carrying a tag | one-line dead branch | `<p><%= x %></p>` → `<% if (false) { %><p><%= x %></p><% } %>` |
| Inside a scriptlet body | `//` prefix | `const a = 1;` → `// const a = 1;` |
| Only a delimiter | left alone | `<%` → `<%` |

Every one of those round-trips byte for byte, and every result is compiled
with the real EJS engine in `tests/render/`.

**Why not just let `commentstring` handle it.** It was measured, and a flat
`<%# %s %>` is wrong on four of the five shapes. `<% if (a) { %>` wrapped in
`<%#` throws `Could not find matching close tag for "<%#"` under EJS 6,
because EJS scans from `<%#` to the *first* `%>` and the tag's own `%>` closes
the comment early. A lone `<%` breaks the same way. And with a Tree-sitter
comment plugin resolving `commentstring` per region, `<p><%= x %></p>` becomes
`<!-- <p><%= x %></p> -->` — which compiles, but still **evaluates** `x` and
ships the result to the browser inside an HTML comment, so it is not commented
out at all.

The dead branch is the one EJS construct that suppresses a line containing a
tag. On a single line it costs no line count, it nests, and it is strictly
safer than what it replaces: the content is never evaluated, so commenting out
a line that reads an undefined local stops throwing rather than starting to.

`commentstring` is still set — to `<% if (false) { %>%s<% } %>` rather than
`<%# %s %>` — as the fallback for anything that bypasses these mappings. It is
the better static token for the same reason: it compiles on any markup
selection whether or not there is a tag in it, where `<%#` compiled only when
there was not.

Set `comment = false` to leave `gc` alone. The `commentstring` fallback stays
either way.

Markup still comments with `<%# %>` rather than `<!-- -->`, unchanged from
`ejs-colorizer`: `<%#` removes the line from the output, while an HTML comment
ships it to the browser. Those are different things, and the server-side one
is what commenting out a template line means.

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

The HTML injection uses `#set! injection.combined` so all `(content)` fragments
are merged into a single virtual HTML document before parsing. This is required
for correctness: without it, each fragment is parsed independently, and
fragments that start mid-document (after a `</script>` tag, for example) cause
the HTML parser to immediately enter error recovery and produce only ERROR
nodes. With `injection.combined` the HTML parser sees a coherent document,
produces proper element nodes including `style_element`, and its own injection
queries fire correctly to inject CSS inside `<style>` blocks. The JavaScript
injections do not use `injection.combined`. Each `(code)` block is parsed as
an independent JS fragment, because concatenating disconnected scriptlet blocks
rarely produces valid JavaScript.

#### CSS inside `<style>` blocks

CSS highlighting works via a three-level injection chain:
`embedded_template` -> `html` -> `css`. The HTML parser must find a
`style_element` node and inject CSS into its content.

The plugin ships `queries/html/injections.scm` with a `style_element` ->
CSS rule. This guarantees the injection is available regardless of what the
system's HTML queries contain.

The `css` Tree-sitter parser binary must be installed for this to work. If CSS
is not highlighting, run `:checkhealth ejs` (a missing `css` parser will show
as a warning) then run `:TSInstall css`.

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

## Development

```sh
nvim -l tests/run.lua
```

No test framework and no plugin dependencies. Include resolution is tested
against a real temporary project tree rather than mocks. The code-region tests
run every case twice — once through the Tree-sitter parse tree and once with
the parser forced unavailable — because both backends have to give the same
answer or they will drift apart.

## License

MIT. See [LICENSE](LICENSE).
