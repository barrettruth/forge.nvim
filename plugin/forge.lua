if vim.g.loaded_forge then
  return
end
vim.g.loaded_forge = true

vim.keymap.set('n', '<Plug>(forge-issue-open)', function()
  require('forge.issue').open_at_cursor()
end, { desc = 'open the issue under the cursor' })

vim.keymap.set('n', '<Plug>(forge-up)', function()
  require('forge.issue').up()
end, { desc = 'go up to the issue list' })

vim.keymap.set('n', '<Plug>(forge-web)', function()
  require('forge.issue').web()
end, { desc = 'open this view on github.com' })

vim.keymap.set('n', '<Plug>(forge-issue-next-page)', function()
  require('forge.issue').page(1)
end, { desc = 'the next page of issues' })

vim.keymap.set('n', '<Plug>(forge-issue-prev-page)', function()
  require('forge.issue').page(-1)
end, { desc = 'the previous page of issues' })

vim.keymap.set('n', '<Plug>(forge-issue-state)', function()
  require('forge.issue').toggle_state()
end, { desc = 'toggle open and closed issues' })

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
      require('forge.issue').open(args.match)
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
