local M = {}

--- Whether `lhs` is already mapped in `buf` itself.
---
--- Only buffer-local mappings count. A global mapping is precisely what a view
--- like this is meant to shadow, and core maps several of the keys we want.
--- @param buf integer
--- @param mode string
--- @param lhs string
--- @return boolean
local function mapped_in(buf, mode, lhs)
  local want = vim.keycode(lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if vim.keycode(map.lhs) == want then
      return true
    end
  end
  return false
end

--- Map `lhs` to `plug` in `buf`, unless the user got there first.
--- @param buf integer
--- @param mode string
--- @param lhs string
--- @param plug string
--- @param desc string
function M.buf_default(buf, mode, lhs, plug, desc)
  local claimed = vim.api.nvim_buf_call(buf, function()
    return vim.fn.hasmapto(plug, mode) == 1
  end)
  if claimed or mapped_in(buf, mode, lhs) then
    return
  end
  vim.keymap.set(mode, lhs, plug, { buffer = buf, remap = true, desc = desc })
end

return M
