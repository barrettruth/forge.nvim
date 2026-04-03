local buf = vim.api.nvim_get_current_buf()
local ns = vim.api.nvim_create_namespace('test_hl')

local section_hl = vim.api.nvim_get_hl(0, { name = 'ForgeLogSection', link = false })
local pass_hl = vim.api.nvim_get_hl(0, { name = 'ForgePass', link = false })
print('ForgeLogSection resolved: ' .. vim.inspect(section_hl))
print('ForgePass resolved: ' .. vim.inspect(pass_hl))
