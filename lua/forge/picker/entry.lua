local M = {}

---@param entry forge.PickerEntry?
---@return table?
function M.value(entry)
  if type(entry) ~= 'table' or rawget(entry, 'placeholder') or rawget(entry, 'load_more') then
    return nil
  end
  local value = rawget(entry, 'value')
  if type(value) ~= 'table' then
    return nil
  end
  return value
end

return M
