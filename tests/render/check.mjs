// Compile every toggle result with the real EJS engine. This is the only
// check that does not share the assumption being tested: the strings look
// reasonable and only EJS knows whether they are.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

// Resolved from the working directory rather than from this file, so `ejs`
// can be installed anywhere convenient and never has to land in the repo.
const require = createRequire(process.cwd() + '/');
let ejs;
try {
  ejs = require('ejs');
} catch {
  console.error('  ejs is not installed here. Run `npm install ejs` in this directory first.');
  process.exit(2);
}

const LOCALS = { name: 'NAME', title: 'TITLE', show: true, n: 2, a: 1, b: 2 };
const cases = JSON.parse(readFileSync('/tmp/toggles.json', 'utf8'));

let roundTripFails = 0;
let compileFails = [];
let leaks = [];
let ok = 0;

// A selection that takes one half of a brace pair is required to break, the
// same as it would in JavaScript. Count braces inside <% %> on the selected
// lines only.
function splitsBracePair(original, first, last) {
  const lines = original.split('\n');
  const sel = lines.slice(first - 1, last).join('\n');
  const code = [...sel.matchAll(/<%[^=\-#]?([\s\S]*?)%>/g)].map((m) => m[1]).join('');
  const open = (code.match(/{/g) || []).length;
  const close = (code.match(/}/g) || []).length;
  return open !== close;
}

for (const c of cases) {
  if (c.roundtrip !== c.original) {
    roundTripFails++;
    console.log(`  ROUND TRIP  ${c.template} [${c.first}-${c.last}]`);
    console.log(`      expected: ${JSON.stringify(c.original)}`);
    console.log(`      got:      ${JSON.stringify(c.roundtrip)}`);
    continue;
  }

  let rendered = null;
  try {
    rendered = ejs.render(c.commented, LOCALS);
  } catch (e) {
    if (!splitsBracePair(c.original, c.first, c.last)) {
      compileFails.push({ ...c, err: String(e.message).split('\n')[0] });
    }
    continue;
  }

  if (/<%|%>/.test(rendered)) {
    leaks.push({ ...c, rendered });
    continue;
  }
  ok++;
}

console.log(`\n  selections:            ${cases.length}`);
console.log(`  round-trip failures:   ${roundTripFails}`);
console.log(`  compile failures:      ${compileFails.length}  (excluding split brace pairs)`);
console.log(`  raw delimiter leaks:   ${leaks.length}`);
console.log(`  compiled clean:        ${ok}`);

for (const f of compileFails.slice(0, 6)) {
  console.log(`\n  COMPILE  ${f.template} [${f.first}-${f.last}]  ${f.err}`);
  console.log(`      ${JSON.stringify(f.commented)}`);
}
for (const f of leaks.slice(0, 6)) {
  console.log(`\n  LEAK  ${f.template} [${f.first}-${f.last}]`);
  console.log(`      ${JSON.stringify(f.rendered)}`);
}

process.exit(roundTripFails === 0 && compileFails.length === 0 && leaks.length === 0 ? 0 : 1);
