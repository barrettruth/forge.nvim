local buf = vim.api.nvim_get_current_buf()

vim.bo[buf].commentstring = ''

require('forge.map').buf_default(
  buf,
  'n',
  '<CR>',
  '<Plug>(forge-issue-open)',
  'open the issue under the cursor'
)
