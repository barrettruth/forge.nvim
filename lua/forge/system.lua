local M = {}

---@param text any
---@return string?
local function trim(text)
  if type(text) ~= 'string' then
    return nil
  end
  local value = vim.trim(text)
  if value == '' then
    return nil
  end
  return value
end

---@param result forge.SystemResult
---@param fallback string
---@return string
function M.cmd_error(result, fallback)
  return trim(result.stderr) or trim(result.stdout) or fallback
end

return M
