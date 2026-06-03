# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
