# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.7] - 2026-06-05

### Fixed

- CSS inside `<style>` blocks was still not highlighted. Debugging revealed
  that the `queries/html/injections.scm` on this system only contained a Python
  injection for `<py-script>` elements and no `style_element` -> CSS rule. The
  HTML sub-parser therefore never spawned a CSS child parser. Added
  `queries/html/injections.scm` to the plugin with `;; extends` and an explicit
  `(style_element (raw_text) @injection.content)` -> CSS pattern. Because the
  file uses `;; extends`, it stacks on top of any existing HTML injection
  queries in the runtimepath without replacing them.

## [1.0.6] - 2026-06-05

### Fixed

- Restored `#set! injection.combined` on the HTML injection, reverting the
  1.0.5 change. Without `injection.combined`, each `(content)` fragment is
  parsed as an independent HTML document. Fragments that start mid-document
  (after a `</script>` closing tag, for example) cause the HTML parser to enter
  error recovery immediately, producing only ERROR nodes. No `style_element`
  node is ever produced, so the HTML parser's own CSS injection query never
  fires and CSS gets no highlighting at all. With `injection.combined` the
  fragments are merged into a coherent virtual HTML document, the HTML parser
  produces proper element nodes, and the CSS injection chain works correctly.
  The earlier claim that `injection.combined` caused CSS position misalignment
  was incorrect -- it was based on a misreading of Neovim's nested injection
  offset handling.

## [1.0.5] - 2026-06-05

### Fixed

- CSS inside `<style>` blocks was not highlighted despite the CSS parser being
  active. The cause was `#set! injection.combined` on the HTML injection.
  Combined injection causes Neovim to merge all `(content)` fragments into a
  virtual document, then map CSS sub-injection positions back through two offset
  layers (virtual HTML document to virtual EJS content document to real buffer).
  That double mapping misaligns most CSS capture ranges, so only short tokens
  like hex color literals (where the offset error still overlaps the right
  characters) survived. Removed `injection.combined` from the HTML injection so
  each `(content)` fragment is parsed as an independent HTML document. A
  `<style>` block with no EJS tags inside it lives in a single complete
  fragment, giving the HTML parser a well-formed element to inject CSS into with
  a single-layer position mapping that works correctly.

## [1.0.4] - 2026-06-05

### Added

- CSS highlighting inside `<style>` blocks now works out of the box. It was
  already supported by the injection chain (content nodes are injected as HTML,
  and the HTML parser's own injection queries inject CSS into `<style>`
  elements) but neither the health check nor the README flagged the `html` and
  `css` parsers as requirements, so users would silently get no highlighting.
  Added health checks for both parsers and updated the post-install
  `:TSInstall` step to include `html` and `css` alongside `embedded_template`.

## [1.0.3] - 2026-06-03

### Fixed

- JavaScript was still not highlighted after the 1.0.2 query fix. The root
  cause was `#set! injection.combined` on the JavaScript injections. With
  `injection.combined`, Neovim concatenates all `(code)` node texts into a
  single virtual JS document before parsing. Disconnected scriptlet blocks
  rarely form valid JavaScript when concatenated, so the TS parser returns an
  error tree with no highlights. Removed `injection.combined` from both
  `(directive (code))` and `(output_directive (code))` patterns so each block
  is parsed as an independent JS fragment. `injection.combined` is retained for
  the HTML `(content)` injection where combining fragments is correct.
  Additionally moved predicates inside the outer pattern for unambiguous capture
  scoping.
- Query files were located in `queries/ejs/` which Neovim never reads.
  `vim.treesitter.language.register('embedded_template', 'ejs')` causes
  Neovim to resolve the language as `embedded_template` and load queries from
  `queries/embedded_template/`. Moved both `injections.scm` and
  `highlights.scm` to `queries/embedded_template/`.

## [1.0.2] - 2026-06-03

### Fixed

- JavaScript was not highlighted inside `<% %>` scriptlet blocks. The
  injection query was matching bare `(code)` nodes at the top level, but the
  grammar wraps `(code)` as a child of `(directive)` or `(output_directive)`.
  Updated `queries/ejs/injections.scm` to match `(directive (code))` and
  `(output_directive (code))` explicitly so JS injection works across all
  scriptlet types.

## [1.0.1] - 2026-06-03

### Fixed

- `ts_ls` no longer sends `textDocument/documentHighlight` requests when the
  cursor is on an HTML `(content)` node, eliminating the recurring
  `-32603: Request textDocument/documentHighlight failed` error notification.
  The capability is disabled on the `ts_ls` client at attach time and replaced
  with a buffer-local `CursorHold` autocmd that routes the request to `ts_ls`
  only when the cursor is inside a `(code)` node (a `<% %>` block). Stale
  highlights are cleared when the cursor moves back into HTML content.

## [1.0.0] - 2026-06-02

### Added

- `ftdetect/ejs.lua`: registers the `ejs` filetype for `.ejs` files via
  `vim.filetype.add()`.
- `plugin/ejs.lua`: minimal bootstrap that defers `require('ejs').setup()` to
  the first `FileType ejs` event. Registers the `:EjsHealth` user command.
- `queries/ejs/injections.scm`: injects `html` into `(content)` nodes and
  `javascript` into `(code)` nodes using the `embedded_template` parser.
  Both injections use `#set! injection.combined`. File starts with
  `;; extends` to preserve upstream query files.
- `queries/ejs/highlights.scm`: stub highlights query starting with
  `;; extends`, delegating to upstream grammars.
- `lua/ejs/config.lua`: default config table with `treesitter`, `lsp`, and
  `snippets` options, all defaulting to `true`.
- `lua/ejs/init.lua`: `setup()` entry point. Merges user options with
  defaults, dispatches to submodules, and guards against repeated calls via
  `vim.g.loaded_ejs_nvim`.
- `lua/ejs/treesitter.lua`: registers the `embedded_template` parser for the
  `ejs` filetype via `vim.treesitter.language.register('embedded_template', 'ejs')`.
- `lua/ejs/lsp.lua`: attaches `html` (vscode-html-language-server) and `ts_ls`
  (typescript-language-server) to EJS buffers via a `FileType ejs` autocmd.
  Guards against duplicate client attachment with `vim.lsp.get_clients()`.
  Resolves `root_dir` with `vim.fs.root()` and a `vim.fn.getcwd()` fallback.
- `lua/ejs/snippets.lua`: LuaSnip snippets for `ejs` buffers. Wrapped in
  `pcall(require, 'luasnip')` so the module is silent when LuaSnip is absent.
  Includes triggers: `<%=`, `<%-`, `<%`, `<%#`, `ejsinclude`, `ejsfor`,
  `ejsif`, `ejspage`.
- `lua/ejs/health.lua`: `:checkhealth ejs` implementation using `vim.health`.
  Checks Neovim version, `embedded_template` parser, `vscode-html-language-server`,
  `typescript-language-server`, and LuaSnip.
- `README.md`: installation via lazy.nvim, prerequisites, post-install
  `:TSInstall embedded_template` step, configuration reference, health check
  documentation, and snippets reference table.
- `LICENSE`: MIT.
