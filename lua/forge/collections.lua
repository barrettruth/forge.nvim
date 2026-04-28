local M = {}

---@param items any[]?
---@param value any
---@return boolean
function M.list_contains(items, value)
  for _, item in ipairs(items or {}) do
    if item == value then
      return true
    end
  end
  return false
end

---@param items any[]?
---@param value any
---@return boolean
function M.set_contains(items, value)
  return type(items) == 'table' and M.list_contains(items, value)
end

return M
