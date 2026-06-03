-- ejs.nvim bootstrap
-- This file is loaded automatically by Neovim's plugin/ directory scan.
-- It must not call require('ejs') eagerly; instead it defers setup until
-- the first FileType ejs event so the plugin respects lazy-loading.

vim.api.nvim_create_user_command('EjsHealth', function()
  vim.cmd('checkhealth ejs')
end, { desc = 'Run ejs.nvim health checks' })

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'ejs',
  once = true,
  desc = 'ejs.nvim: bootstrap on first EJS buffer',
  callback = function()
    require('ejs').setup()
  end,
})
