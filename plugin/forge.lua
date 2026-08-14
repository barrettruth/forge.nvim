if vim.g.loaded_forge then
  return
end
vim.g.loaded_forge = true

vim.keymap.set(
  'n',
  '<Plug>(forge-help)',
  '<cmd>help forge-mappings<cr>',
  { desc = 'what the keys in this buffer do' }
)

vim.keymap.set('n', '<Plug>(forge-open)', function()
  require('forge.view').open_at_cursor()
end, { desc = 'open the item under the cursor' })

vim.keymap.set('n', '<Plug>(forge-open-split)', function()
  require('forge.view').open_at_cursor(true)
end, { desc = 'open the item under the cursor in a split' })

vim.keymap.set('n', '<Plug>(forge-up)', function()
  require('forge.view').up()
end, { desc = 'go up to the list this item is in' })

vim.keymap.set('n', '<Plug>(forge-refresh)', function()
  require('forge.view').refresh()
end, { desc = 'fetch this view again' })

vim.keymap.set('n', '<Plug>(forge-web)', function()
  require('forge.view').web()
end, { desc = 'open this view on github.com' })

vim.keymap.set('n', '<Plug>(forge-next-page)', function()
  require('forge.view').page(1)
end, { desc = 'the next page' })

vim.keymap.set('n', '<Plug>(forge-prev-page)', function()
  require('forge.view').page(-1)
end, { desc = 'the previous page' })

vim.keymap.set('n', '<Plug>(forge-state)', function()
  require('forge.view').toggle_state()
end, { desc = 'toggle open and closed' })

vim.api.nvim_create_user_command('Issue', function(opts)
  require('forge.issue').open(opts.args)
end, { nargs = '?', desc = 'open a GitHub issue, or the issue list' })

local group = vim.api.nvim_create_augroup('forge', { clear = true })

-- A forge:// buffer has no file behind it, so reading one means fetching it
-- again. This is what makes :edit reload a view instead of emptying it, and
-- what lets :edit forge://... open one from nothing.
vim.api.nvim_create_autocmd('BufReadCmd', {
  group = group,
  pattern = 'forge://*',
  callback = function(args)
    vim.schedule(function()
      local u = require('forge.uri').parse(args.match)
      if u then
        require('forge.view').open(u)
      end
    end)
  end,
})

-- 'winbar' is a window option, so a view shown in a second window would lose
-- the one set when it was drawn.
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  pattern = 'forge://*',
  callback = function(args)
    vim.wo.winbar = vim.b[args.buf].forge_winbar or ''
  end,
})
