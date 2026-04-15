local M = {}

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
  local cfg = require('forge').config()
  local split = opts.split or cfg.ci.split or cfg.split
  local prefix = split == 'vertical' and 'vertical' or 'botright'
  vim.cmd(prefix .. ' new')
  local buf = vim.api.nvim_get_current_buf()
  vim.fn.termopen(cmd)
  if opts.startinsert ~= false then
    vim.cmd('startinsert')
  end

  local keys = cfg.keys and cfg.keys.log or {}
  if keys.browse ~= false and (opts.url or opts.browse_fn) then
    vim.keymap.set('n', keys.browse or 'gx', function()
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
  if keys.close ~= false then
    vim.keymap.set('n', keys.close or 'q', function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, desc = 'Close' })
  end
end

return M
