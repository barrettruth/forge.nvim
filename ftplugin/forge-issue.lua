local buf = vim.api.nvim_get_current_buf()

vim.bo[buf].commentstring = ''

local map = require('forge.map')

map.buf_default(buf, 'n', '<CR>', '<Plug>(forge-issue-open)', 'open the issue under the cursor')
map.buf_default(buf, 'n', '-', '<Plug>(forge-up)', 'go up to the issue list')
