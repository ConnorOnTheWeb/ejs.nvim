# Render check

Compiles every comment-toggle result with the real EJS engine.

`tests/*_spec.lua` asserts the shape of what the toggle produces. This asserts
that EJS accepts it — which is a different question, and the only one that
does not share the assumption being tested. Two of the bugs the toggle now
guards against were invisible from the output string alone: the strings looked
reasonable and only EJS knew they were not.

Not part of `nvim -l tests/run.lua`, because it needs Node and the `ejs`
package and the rest of the suite needs neither.

```sh
npm install ejs
nvim --headless -c "luafile tests/render/generate.lua" -c "qa!"
node tests/render/check.mjs
```

For every contiguous line selection of five representative templates it
asserts three things: the toggle round-trips byte for byte, the commented
result compiles, and no raw `<%` or `%>` leaks into the rendered page.

A selection that takes one half of a brace pair is *required* to break, the
same as it would in JavaScript, and is identified from the selection rather
than waved through — `<% if (show) { %>` commented on its own leaves the
matching `<% } %>` dangling, and EJS should say so.
