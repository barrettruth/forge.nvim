local M = {}

---@param cmd string[]
---@param opts? { split?: forge.Split, url?: string }
function M.open(cmd, opts)
  opts = opts or {}
  local cfg = require('forge').config()
  local split = opts.split or cfg.ci.split or cfg.split
  local prefix = split == 'vertical' and 'vertical' or 'botright'
  vim.cmd(prefix .. ' new')
  local buf = vim.api.nvim_get_current_buf()
  vim.fn.termopen(cmd)
  vim.cmd('startinsert')

  local keys = cfg.keys and cfg.keys.log or {}
  if keys.browse ~= false and opts.url then
    vim.keymap.set('n', keys.browse or 'gx', function()
      vim.ui.open(opts.url)
    end, { buffer = buf, desc = 'Browse' })
  end
  if keys.close ~= false then
    vim.keymap.set('n', keys.close or 'q', function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, desc = 'Close' })
  end
end

return M
