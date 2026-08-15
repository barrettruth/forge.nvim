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

vim.keymap.set('n', '<Plug>(forge-create)', function()
  require('forge.view').create()
end, { desc = 'start something new in this collection' })

vim.keymap.set('n', '<Plug>(forge-web)', function()
  require('forge.view').web()
end, { desc = 'open this view on github.com' })

vim.keymap.set('n', '<Plug>(forge-yank)', function()
  require('forge.view').yank()
end, { desc = "yank this view's url" })

vim.keymap.set('n', '<Plug>(forge-act)', function()
  require('forge.view').act()
end, { desc = 'do something to this issue or pull request' })

vim.keymap.set('n', '<Plug>(forge-checks)', function()
  require('forge.ci').checks()
end, { desc = "show this pull request's checks in ci.nvim" })

vim.keymap.set('n', '<Plug>(forge-diff)', function()
  require('forge.diff').show()
end, { desc = "show this pull request's diff in diffs.nvim" })

vim.keymap.set('n', '<Plug>(forge-log)', function()
  require('forge.commits').show()
end, { desc = "show this pull request's commits in fugitive" })

vim.keymap.set('n', '<Plug>(forge-next-page)', function()
  require('forge.view').page(1)
end, { desc = 'the next page' })

vim.keymap.set('n', '<Plug>(forge-prev-page)', function()
  require('forge.view').page(-1)
end, { desc = 'the previous page' })

vim.api.nvim_create_user_command('Issue', function(opts)
  require('forge.issue').open(opts.args, opts)
end, {
  nargs = '*',
  bar = true,
  complete = function(lead)
    return require('forge.search').complete(lead)
  end,
  desc = 'open a GitHub issue, or the issue list',
})

vim.api.nvim_create_user_command('PR', function(opts)
  require('forge.pr').open(opts.args, opts)
end, {
  nargs = '*',
  bar = true,
  complete = function(lead)
    return require('forge.search').complete(lead)
  end,
  desc = 'open a GitHub pull request, or the pull request list',
})

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

vim.api.nvim_create_autocmd('BufLeave', {
  group = group,
  pattern = 'forge://*',
  callback = function(args)
    require('forge.view').remember(args.buf)
  end,
})

vim.api.nvim_create_autocmd('BufWipeout', {
  group = group,
  pattern = 'forge://*',
  callback = function(args)
    require('forge.view').forget(args.buf)
  end,
})

-- 'winbar' is a window option, so a view shown in a second window would lose
-- the one set when it was drawn.
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  pattern = 'forge://*',
  callback = function(args)
    require('forge.view').dress(args.buf, vim.api.nvim_get_current_win())
  end,
})
