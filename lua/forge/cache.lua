local M = {}

---@class forge.Cache
---@field get fun(key: string): any?
---@field set fun(key: string, value: any)
---@field clear fun(key: string?)
---@field clear_prefix fun(prefix: string)

---@param ttl_seconds integer
---@param clock? fun(): integer
---@return forge.Cache
function M.new(ttl_seconds, clock)
  clock = clock or os.time
  local store = {}
  local cache = {}

  function cache.get(key)
    local entry = store[key]
    if not entry then
      return nil
    end
    if entry.expires_at <= clock() then
      store[key] = nil
      return nil
    end
    return entry.value
  end

  function cache.set(key, value)
    store[key] = { value = value, expires_at = clock() + ttl_seconds }
  end

  function cache.clear(key)
    if key then
      store[key] = nil
      return
    end
    for k in pairs(store) do
      store[k] = nil
    end
  end

  function cache.clear_prefix(prefix)
    for k in pairs(store) do
      if k:sub(1, #prefix) == prefix then
        store[k] = nil
      end
    end
  end

  return cache
end

return M
