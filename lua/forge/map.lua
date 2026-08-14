local M = {}

--- Map `lhs` to `plug` in `buf`, unless the user got there first.
---
--- A default is skipped when the user has already mapped something to `plug`,
--- and when `lhs` already means something in that buffer. Either way their
--- mapping stands, so a default never silently replaces a deliberate choice.
--- @param buf integer
--- @param mode string
--- @param lhs string
--- @param plug string
--- @param desc string
function M.buf_default(buf, mode, lhs, plug, desc)
  local taken = vim.api.nvim_buf_call(buf, function()
    return vim.fn.hasmapto(plug, mode) == 1 or vim.fn.maparg(lhs, mode) ~= ''
  end)
  if taken then
    return
  end
  vim.keymap.set(mode, lhs, plug, { buffer = buf, remap = true, desc = desc })
end

return M
