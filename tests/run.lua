-- Headless test runner: `nvim -l tests/run.lua`
--
-- No external test framework on purpose. These tests exercise pure Lua, a
-- scratch buffer and a temporary fixture tree, all of which `nvim -l`
-- provides, so the suite runs against any Neovim >= 0.10 with nothing
-- installed alongside it.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
-- The plugin root also has to be on the runtimepath, not just package.path,
-- so queries/ and ftplugin/ are found the way they are in real use.
vim.opt.runtimepath:prepend(root)

local M = { passed = 0, failed = 0, current = nil }
_G.T = M

function M.describe(name, fn)
  M.current = name
  fn()
end

function M.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
  else
    M.failed = M.failed + 1
    io.write(string.format('FAIL  %s :: %s\n      %s\n', M.current or '?', name, tostring(err)))
  end
end

function M.eq(expected, actual, msg)
  local function norm(v)
    return type(v) == 'table' and vim.inspect(v) or tostring(v)
  end
  if not vim.deep_equal(expected, actual) then
    error(string.format('%sexpected %s, got %s', msg and (msg .. ': ') or '', norm(expected), norm(actual)), 2)
  end
end

function M.truthy(value, msg)
  if not value then
    error(msg or 'expected a truthy value, got ' .. tostring(value), 2)
  end
end

function M.falsy(value, msg)
  if value then
    error(msg or 'expected a falsy value, got ' .. vim.inspect(value), 2)
  end
end

for _, spec in ipairs(vim.fn.glob(root .. '/tests/*_spec.lua', false, true)) do
  dofile(spec)
end

io.write(string.format('\n%d passed, %d failed\n', M.passed, M.failed))
os.exit(M.failed == 0 and 0 or 1)
