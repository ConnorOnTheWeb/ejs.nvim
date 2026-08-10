# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-08-09

Brings the plugin up to the feature set of `connorontheweb/ejs-colorizer`
v2.3.1 — until now it covered highlighting, LSP attachment and snippets, and
none of the template navigation the extension had gained since v2.1.0 — and
adds completion support for every major Neovim completion engine.

Three of the extension's features are deliberately left out, because in
Neovim they belong to other tools: Emmet expansion, Prettier formatting
(`conform.nvim` or `formatprg`), and the Outline provider (LSP symbols or
`aerial.nvim`). The extension's joined-program JavaScript syntax check is
also skipped: `ts_ls` is already attached to `<% %>` regions by
`lua/ejs/lsp.lua` and reports real syntax errors with better positions than
that heuristic can.

### Added

- **`include()` path completion** inside the quotes, with directories
  offered with a trailing slash and re-triggering so navigating into one
  keeps completing. Paths are offered without the `.ejs` extension, the form
  that actually appears in templates.

- **`gf` and `:EjsDefinition` on include paths.** `ftplugin/ejs.lua` sets
  `suffixesadd` and an `includeexpr`, so plain `gf` on
  `include('partials/head')` opens `views/partials/head.ejs` — resolving the
  missing extension and searching the views root, neither of which `gf` can
  do on its own.

- **Include resolution that handles both conventions** (`lua/ejs/include.lua`):
  file-relative first, matching EJS's own runtime and `ejs-colorizer`'s
  `includeResolver.ts`, then the views root — the nearest ancestor directory
  named `views`, else `<project root>/views`, mirroring how `express-map`
  derives it from `app.set('views', …)`. A leading `/` resolves against the
  views root only. `.ejs`, `.html` and `.htm` are all tried, and
  `include('partials')` finds `partials/index.ejs`.

- **Diagnostics** for an `include()` path that matches no file (the message
  names the directories that were searched), and for a `<%# %>` comment that
  ends early. The latter is the case where the commented-out text itself
  contains a tag, so EJS's scan to the first `%>` closes the comment there
  and the remainder leaks back into the template as markup — the extension's
  v2.2.3 diagnostic.

- **Hover documentation on `K`** for the delimiter under the cursor
  (extension `hoverProvider.ts`). The distinctions worth documenting are the
  ones that are not guessable from the syntax: `<%=` escapes its output and
  `<%-` does not, which is the XSS-relevant difference, and `%>`, `-%>` and
  `_%>` differ in what whitespace they consume. Openers are matched
  longest-first so `<%#` is never read as `<%` with a stray `#`. `K` in an
  EJS buffer already belongs to html-lsp or ts_ls, so the mapping answers
  only on a delimiter and hands off everywhere else.

- **The closing delimiters `-%>`, `_%>` and the v6 `%%>` literal escape**,
  which were missing from the plugin entirely. `%%>` is also now a LuaSnip
  snippet, alongside the `<%%` added above.

- **Completion for EJS tags and block scaffolds**, served to nvim-cmp,
  blink.cmp and Neovim's built-in completion from one core. This includes
  the v6 `<%%` literal escape (extension v2.2.7), which was missing from the
  snippets entirely, and the `ejsif` / `ejsfor` / `ejsinclude` / `ejspage`
  scaffolds — previously LuaSnip-only, and therefore invisible to anyone
  using a different snippet engine or none.

- **blink.cmp support**, registered automatically for the `ejs` filetype via
  its runtime API (blink >= v1.6). Verified against blink's own source that
  this appends to a separate per-filetype list and cannot displace the
  sources you configured yourself.

- **A complete-function** (`completion.omni = true`) for Neovim 0.12's
  built-in completion, mini.completion and coq_nvim. On 0.12 it is appended
  to `'complete'` as `FEjsCompleteFunc` rather than claiming `omnifunc`,
  which in an EJS buffer is already held by html-lsp or ts_ls.

- **`commentstring`.** `.ejs` had none at all, so `gc` in an EJS buffer
  reported an empty `commentstring` rather than commenting anything.
  `ftplugin/ejs.lua` now sets `<%# %s %>`; because Neovim resolves the comment
  string from the deepest Tree-sitter tree at the cursor, and this plugin
  already injects `html` and `javascript`, `gc` produces `<!-- -->` in markup
  and `//` inside `<% %>` with no further work. This is deliberately
  region-aware rather than always emitting `<%# %>` like the extension's
  comment toggle does, because that is how Neovim behaves in every other
  embedded language.

- **Folding for control-flow blocks** (`lua/ejs/fold.lua`). Tree-sitter
  cannot express these: `<% if (x) { %>` and `<% } %>` are two independent
  `directive` nodes with the HTML between them belonging to neither, so no
  single node spans the block. Brace depth inside the code regions is what
  actually delimits it, counted with string, comment and `<%%`-escape
  awareness so `<% const s = "}" %>` does not unbalance the file. Folds start
  open, and the per-line depths are cached per `changedtick`.

- **A test suite**, run with `nvim -l tests/run.lua` and needing no test
  framework or plugin dependencies. 31 tests covering completion contexts,
  include resolution against a real fixture tree, diagnostics and folding.

### Changed

- **`config.snippets` now controls LuaSnip only**; the new
  `config.completion` table controls the completion source, which offers the
  same tags and scaffolds independently. LuaSnip is no longer reported as a
  warning by `:checkhealth ejs` when absent, because it is now genuinely
  optional rather than the only way to get snippets.

## [1.0.9] - 2026-06-05

### Changed

- Removed the `pcall(require('lazy').load({ plugins = { 'nvim-treesitter' } }))`
  call that was added in 1.0.8. That change was based on a wrong diagnosis: the
  actual cause of CSS not highlighting was that the `css` Tree-sitter parser
  binary was not installed, not a load-order issue. The call was unnecessary and
  has been removed.
- Simplified the README CSS section to accurately describe the real requirement:
  the `css` parser binary must be installed via `:TSInstall css`.
- Fixed comment numbering in `lua/ejs/health.lua` (checks were numbered 6, 7,
  8 after inserting two new checks in 1.0.4 without renumbering the rest).

## [1.0.8] - 2026-06-05

### Fixed

- CSS inside `<style>` blocks was still not highlighting. The root cause was a
  load-order issue: ejs.nvim loads on `FileType ejs`, but nvim-treesitter (which
  contains the `html_tags/injections.scm` file with the `style_element` -> CSS
  rule) had not yet been loaded at that point, so its `runtime/` directory was
  not in runtimepath when the embedded_template parser began processing the
  buffer. Added a `pcall(require('lazy').load(...))` call in
  `lua/ejs/treesitter.lua` to force nvim-treesitter to load before the parser
  is registered. The call is wrapped in `pcall` so it is a no-op on setups
  that do not use lazy.nvim or do not have nvim-treesitter installed.

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
