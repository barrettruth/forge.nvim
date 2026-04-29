local M = {}

local config_mod = require('forge.config')

---@class forge.TermOpts
---@field split? forge.Split
---@field url? string
---@field browse_fn? fun(buf: integer): string?
---@field enter_fn? fun(buf: integer)
---@field startinsert? boolean

---@param cmd string[]
---@param opts? forge.TermOpts
function M.open(cmd, opts)
  opts = opts or {}
  local cfg = config_mod.config()
  local split = opts.split or cfg.ci.split or cfg.split
  local prefix = split == 'vertical' and 'vertical' or 'botright'
  vim.cmd(prefix .. ' new')
  local buf = vim.api.nvim_get_current_buf()
  vim.fn.termopen(cmd)
  if opts.startinsert == true then
    vim.cmd('startinsert')
  end

  if opts.url or opts.browse_fn then
    vim.keymap.set('n', 'gx', function()
      local url = opts.browse_fn and opts.browse_fn(buf) or opts.url
      if not url then
        url = opts.url
      end
      if url then
        vim.ui.open(url)
      end
    end, { buffer = buf, desc = 'Browse' })
  end
  if opts.enter_fn then
    vim.keymap.set('n', '<cr>', function()
      opts.enter_fn(buf)
    end, { buffer = buf, desc = 'Open' })
  end
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, desc = 'Close' })
end

return M
