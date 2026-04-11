local M = {}

---@type table<string, { data: string[]?, ts: number }>
local cache = {}

local TTL = 300

---@type string?
local last_context

---@param line string
---@return string?
local function detect_field(line)
  if line:match('^%s*Draft:') then
    return 'draft'
  elseif line:match('^%s*Labels:') then
    return 'labels'
  elseif line:match('^%s*Assignees:') then
    return 'assignees'
  elseif line:match('^%s*Reviewers:') then
    return 'reviewers'
  elseif line:match('^%s*Milestone:') then
    return 'milestone'
  end
  return nil
end

---@return boolean
local function in_comment_block()
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cur = vim.fn.line('.')
  local inside = false
  for i = 1, cur do
    if buf_lines[i]:match('^<!--') then
      inside = true
    elseif buf_lines[i]:match('^%-%->') then
      inside = false
    end
  end
  return inside
end

---@param line string
---@param col integer
---@return string? trigger
---@return integer? start_col
local function detect_trigger(line, col)
  local i = col - 1
  while i > 0 do
    local ch = line:sub(i, i)
    if ch == '#' or ch == '@' then
      if i == 1 or line:sub(i - 1, i - 1):match('[%s(]') then
        return ch, i
      end
      return nil, nil
    elseif not ch:match('[%w_%-]') then
      return nil, nil
    end
    i = i - 1
  end
  return nil, nil
end

---@param field string
---@param f forge.Forge
---@param scope? table
---@return string[]
local function fetch(field, f, scope)
  if field == 'draft' then
    return { 'true', 'false' }
  end

  local now = os.time()
  local key = f.name .. ':' .. field .. ':' .. require('forge').scope_key(scope)
  local entry = cache[key]
  if entry and entry.data and (now - entry.ts) < TTL then
    return entry.data
  end

  local cmd = f:completion_cmd(field, scope)
  if not cmd then
    return {}
  end

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return (entry and entry.data) or {}
  end

  local items = vim.split(vim.trim(result.stdout or ''), '\n', { plain = true, trimempty = true })
  cache[key] = { data = items, ts = now }
  return items
end

function M.clear()
  cache = {}
end

---@param findstart integer
---@param base string
---@return integer|table[]
function M.omnifunc(findstart, base)
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col('.')

  if findstart == 1 then
    if in_comment_block() then
      local field = detect_field(line)
      if field then
        last_context = 'field:' .. field
        local i = col - 1
        while i > 0 and line:sub(i, i):match('[^,%s]') do
          i = i - 1
        end
        return i
      end
    end

    local trigger, tpos = detect_trigger(line, col)
    if trigger and tpos then
      last_context = 'trigger:' .. trigger
      return tpos
    end

    last_context = nil
    return -1
  end

  if not last_context then
    return {}
  end

  local f = require('forge').detect()
  if not f then
    return {}
  end
  local scope = vim.b.forge_scope

  local kind, value = last_context:match('^(%w+):(.+)$')

  if kind == 'field' then
    local candidates = fetch(value, f, scope)
    local items = {}
    local lower_base = base:lower()
    for _, word in ipairs(candidates) do
      if word:lower():find(lower_base, 1, true) then
        table.insert(items, { word = word, menu = '[Forge]' })
      end
    end
    return items
  end

  if kind == 'trigger' then
    if value == '#' then
      local candidates = fetch('issues', f, scope)
      local items = {}
      local lower_base = base:lower()
      for _, entry in ipairs(candidates) do
        local num, title = entry:match('^(%d+)\t(.+)$')
        if num then
          if num:find(lower_base, 1, true) or title:lower():find(lower_base, 1, true) then
            table.insert(items, { word = '#' .. num, menu = title })
          end
        end
      end
      return items
    elseif value == '@' then
      local candidates = fetch('mentions', f, scope)
      local items = {}
      local lower_base = base:lower()
      for _, word in ipairs(candidates) do
        if word:lower():find(lower_base, 1, true) then
          table.insert(items, { word = '@' .. word, menu = '[User]' })
        end
      end
      return items
    end
  end

  return {}
end

return M
