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

---@param url any
---@return string?
function M.normalize(url)
  local value = trim(url)
  if not value then
    return nil
  end
  local normalized = tostring(value)
  normalized = normalized:gsub('%.git$', '')
  normalized = normalized:gsub('^ssh://git@', 'https://')
  normalized = normalized:gsub('^git@([^:]+):', 'https://%1/')
  normalized = normalized:gsub('/+$', '')
  normalized = normalized:gsub('#.*$', '')
  normalized = normalized:gsub('%?.*$', '')
  return normalized
end

---@param url any
---@return string?, string?
function M.split(url)
  local normalized = M.normalize(url)
  if not normalized then
    return nil
  end
  local host, path = normalized:match('^https?://([^/]+)/(.+)$')
  if not host or not path then
    return nil
  end
  path = path:match('^(.-)/%-/') or path
  path = path:gsub('/+$', '')
  if path == '' then
    return nil
  end
  return host, path
end

return M
