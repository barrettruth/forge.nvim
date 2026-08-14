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

vim.api.nvim_create_user_command('Issue', function(opts)
  require('forge.issue').open(opts.args)
end, { nargs = '?', desc = 'open a GitHub issue, or the issue list' })
