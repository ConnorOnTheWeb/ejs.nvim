# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-08-22

Catches this plugin up to `connorontheweb/ejs-colorizer` v2.5.0. Two of the
three outstanding items needed work; the third was already done here, and
earlier than upstream.

### Added

- **`gc` and `gcc` comment each line in the style its own shape calls for.**
  `commentstring` is a single string, and an EJS template is made of five
  distinguishable line shapes with only one of them taking `<%# … %>`:

  | Where the line is | Style | Result |
  |---|---|---|
  | Markup or text | `<%# … %>` wrap | `<p>Hi</p>` → `<%# <p>Hi</p> %>` |
  | One whole EJS tag | `#` marker on the tag | `<% if (a) { %>` → `<%#if (a) { %>` |
  | Markup carrying a tag | one-line dead branch | `<p><%= x %></p>` → `<% if (false) { %>…<% } %>` |
  | Inside a scriptlet body | `//` prefix | `const a = 1;` → `// const a = 1;` |
  | Only a delimiter | left alone | `<%` → `<%` |

  Ported from ejs-colorizer v2.5.0, which arrived at that table by compiling
  every result with the real EJS engine. `comment = false` opts out.

- **The marker style drops the space after `<%`**, which is what makes toggling
  off unambiguous. The wrap style always leaves one and the marker style never
  does, so the character at index 3 identifies which style produced a
  commented line — without it, `<%# if (a) { %>` could have come from either
  and the two uncomment to different things, one of them silently deleting a
  tag. A delimiter marker is preserved: `<%= x %>` toggles to `<%#= x %>` and
  back, not to a scriptlet that cannot parse.

- **Uncommenting goes by the style that produced the line, not by the line's
  shape.** Commenting changes what a line classifies as — `<p>Hi</p>` is
  markup, and `<%# <p>Hi</p> %>` is a whole tag — so classifying the commented
  line and uncommenting off *that* strips the wrong delimiters. This was a
  real bug in the first draft here, caught by the round-trip assertions.

- **Per-check diagnostic severities**, ported from v2.4.0: `missing_include`
  and `broken_comment` each take `error`, `warn`, `info`, `hint` or `off`.
  `hint` is the useful one — it leaves the underline in the buffer while
  keeping the entry out of the location list. Each diagnostic now also carries
  a `code` (`missing-include`, `broken-comment`).

  `diagnostics = true | false` still works and maps to both checks on or off.

  There is no third setting because the extension's JavaScript syntax check is
  still deliberately not ported: `ts_ls` is attached to `<% %>` regions and
  reports real syntax errors there with better positions than a
  joined-program heuristic can.

- **`tests/render/`, which compiles every toggle result with the real EJS
  engine.** For every contiguous line selection of five representative
  templates it asserts the toggle round-trips byte for byte, the result
  compiles, and no raw `<%` or `%>` leaks into the rendered page. 56
  selections; 48 compile clean and the other 8 are required to break, and are
  identified from the selection rather than waved through — commenting one
  half of a brace pair has to fail exactly as it would in JavaScript.

  Not part of `nvim -l tests/run.lua`: it needs Node and the `ejs` package,
  and the rest of the suite needs neither. It exists because handing the
  result to EJS is the only check that does not share the assumption being
  tested.

### Changed

- **`commentstring` is now the dead branch, `<% if (false) { %>%s<% } %>`,
  rather than `<%# %s %>`.** It is only a fallback now that `gc` is
  overridden, and it is the strictly better one: it compiles on any markup
  selection whether or not there is a tag in it, where `<%#` compiled only
  when there was not.

### Fixed

- **`gc` produced templates that would not compile, on four of the five line
  shapes.** The README claimed Tree-sitter region resolution already handled
  this. It does not, and it was measured rather than assumed — every shape run
  through the real `gcc` and the result handed to EJS:

  - `<% if (a) { %>` → `<%# <% if (a) { %> %>`, which **throws**
    `Could not find matching close tag for "<%#"`.
  - a lone `<%` → `<%# <% %>`, which throws the same way, and does something
    worse than fail: commenting a delimiter changes the block structure the
    rest of the selection was classified against, so the next `gc` comments
    again instead of uncommenting.
  - `<p><%= x %></p>` → `<!-- <p><%= x %></p> -->` with a Tree-sitter comment
    plugin resolving per region. That compiles, and is worse for it: `x` is
    still **evaluated** and its output shipped to the browser inside an HTML
    comment, so the line is not commented out at all.
  - plain markup → `<!-- … -->` rather than `<%# … %>`, which ships the line
    to the browser instead of removing it from the output.

  Only the scriptlet-body case was already right.

- **`:checkhealth ejs` printed severity names as single letters.**
  `vim.diagnostic.severity` carries short aliases (`E`, `W`, `I`, `N`)
  alongside the long names and both directions of the mapping, so a reverse
  lookup with `pairs` returned whichever key it reached first — `warn` came
  out as `w`. Replaced with an explicit map.

### Notes

- **89 tests passing, up from 54.** The new ones cover classification of all
  five shapes, the style each produces, byte-for-byte round trips for eight
  line forms, style detection, mixed-selection toggling, and the severity
  settings.

- **Already done, and earlier than upstream: include-path completion
  scoping.** ejs-colorizer's v2.5.0 closes the Known item it carried since
  v2.3.2 — typing `include('` in body text opened a file picker. This plugin
  fixed that in 1.1.1, and did not need the trailing-region machinery the
  extension had to add: an unterminated `<%` yields a `code` node running to
  the end of the buffer, so the parse tree answers "is this a tag being typed"
  directly. Re-verified against every case v2.5.0 lists — prose, `<script>`
  bodies, attribute values, HTML comments and a stray `%>` all offer nothing,
  a tag being typed offers completions at end-of-file and mid-file alike, and
  editing an existing include in a closed tag still works.

## [1.1.1] - 2026-08-10

### Fixed

- **`include()` was detected anywhere in the buffer, not only inside EJS
  tags.** `<p>Plain <code>include('partials/head')</code> opens it.</p>`
  reported an unresolved include, as did `include("layouts/base")` in body
  text, `include('partials/legacy')` inside an `<!-- -->` comment, and
  `include('partials/old')` inside a `<%# %>` comment. Any `include()`-shaped
  text in a template produced a warning.

  The cause was scope, not the pattern. `find_includes` iterated every line
  and applied `INCLUDE_PATTERN` with no notion of where the `<% %>` regions
  are. Tightening the pattern was not the answer: a guard has to enumerate the
  ways text can fail to be code — prose, comments, attribute values, script
  bodies — and that set has no end. The sibling projects reached the same
  conclusion from the other direction; `connorontheweb/alpinejs-tools` v1.7.3
  abandoned the guard route after two attempts and records why, and
  `connorontheweb/ejs-colorizer` v2.3.2 fixes the identical bug in its own
  `findIncludes`. The invariant that settles it is that an `include()` call is
  only ever inside an EJS tag.

  Regions now come from the Tree-sitter parse tree, in a new
  `lua/ejs/region.lua`. That is the same structural question `lua/ejs/lsp.lua`
  was already asking with `vim.treesitter.get_node()` to route
  `documentHighlight`, in the cursor form rather than the range form; that
  private copy is gone and it calls the shared helper now.

- **This was never diagnostics-only.** `find_includes` also drives
  `:EjsDefinition`, and the completion path had the same root cause by a
  different route: `get_context` decided from the line prefix alone, so typing
  `include('` in body text offered partial paths. Milder — it offers rather
  than warns — but the same bug, and it now consults the same helper.
  Completion is where this plugin does better than the extension, which left
  its own completion provider uncovered because its block scanner cannot see
  into a tag the author has not closed yet. The parse tree can: an unterminated
  `<%` yields a `code` node running to the end of the buffer, so paths are
  still offered mid-edit, which is the only moment completion ever fires.

### Changed

- **`<%# %>` comments are the one place the features deliberately disagree.**
  A commented-out `include()` no longer produces a missing-path warning,
  because a warning about an include you commented out is noise you didn't ask
  for. `:EjsDefinition` and completion still follow it, because those only
  answer where the cursor already is. `gf` was never affected either way — it
  goes through `includeexpr` and resolves `<cfile>` directly, without
  consulting `find_includes` at all.

  The grammar makes this nearly free: `<%# x %>` parses as `comment_directive`
  with a `(comment)` child, not `(code)`, so the region query decides it
  rather than a special case. `include_comments` is a required option on
  `code_regions` and `find_includes` with no default, so a new caller has to
  state its intent instead of silently inheriting the wrong one — two copies
  drifting apart is how this class of bug survives.

- **A missing `embedded_template` parser falls back to a text scan for
  `<% %>` spans**, rather than reporting nothing. `:checkhealth ejs` treats
  the missing parser as an Error, but the plugin still loads and everything
  else still works, and `find_includes` drives `:EjsDefinition` as well as the
  diagnostic — so reporting nothing would have turned a false-positive bug
  into a missing feature. The fallback fixes all four reported cases on its
  own, since none of them contain a `<%` at all. It is one branch of one
  function returning the same shape as the other, and the tests run every case
  through both.

- **`lua/ejs/fold.lua` was left alone.** `line_delta` models the same "only
  text inside `<% %>` counts" rule, but it computes per-line deltas with
  string and comment awareness *inside* the code, which a span helper does not
  provide — it would still have to re-scan. Rewriting it on top of
  `region.lua` would have risked the folding behaviour for no user-visible
  gain.

### Known

- **`<% const s = "include('x')" %>` is still reported.** An `include()` inside
  a JavaScript string sits inside a genuine EJS tag, so the gate admits it.
  Excluding it would mean parsing JS string and comment syntax — exactly the
  guard enumeration this fix rejects. There is a test pinning this, so the
  boundary is deliberate rather than forgotten.

### Verified

- 54 tests, `nvim -l tests/run.lua`, up from 37. Covering each of the four
  reported cases (0 matches, previously 1 each), a genuine broken include in
  `<%- %>` and a working include (still flagged and still clean), one include
  in each of `<% %>`, `<%= %>`, `<%- %>` and `<%_ %>`, a `<%# %>` include
  under both settings of the comment flag (0 for diagnostics, 1 for
  navigation), a code region spanning several lines, the `<%%` literal escape,
  prose and a real include in the same buffer (1 match, not 2, and on the
  right line), an unterminated tag, completion refusing `include('` in body
  text while still offering it inside a tag, and both region backends asserted
  to agree on every one of those.

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
  framework or plugin dependencies. 37 tests covering completion contexts,
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
