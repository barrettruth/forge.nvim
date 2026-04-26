local M = {}

local state = {}

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

---@param value any
---@return string?
local function stringify(value)
  if value == nil then
    return nil
  end
  return trim(tostring(value))
end

---@param result forge.SystemResult
---@return forge.PickerSessionFailure
local function command_failure(result)
  return {
    kind = 'command',
    result = result,
    message = trim(result.stderr) or trim(result.stdout),
  }
end

---@param result forge.SystemResult
---@param decode_error any
---@return forge.PickerSessionFailure
local function decode_failure(result, decode_error)
  local decode_message = stringify(decode_error)
  return {
    kind = 'decode',
    result = result,
    message = trim(result.stderr) or decode_message or trim(result.stdout),
    decode_error = decode_message,
  }
end

local function scope(key)
  local item = state[key]
  if not item then
    item = { epoch = 0, inflight = false }
    state[key] = item
  end
  return item
end

local function resolve(value)
  if type(value) == 'function' then
    return value()
  end
  return value
end

local function emit_entries(emit, entries)
  for _, entry in ipairs(entries) do
    emit(entry)
  end
  emit(nil)
end

local function request_json(key, cmd, callback)
  local token = M.begin(key)
  vim.system(resolve(cmd), { text = true }, function(result)
    vim.schedule(function()
      M.finish(key, token)
      if not M.current(key, token) then
        callback(false, nil, nil, true)
        return
      end
      local ok, data, failure = M.decode_json(result)
      callback(ok, data, failure, false)
    end)
  end)
end

M.request_json = request_json

function M.begin(key)
  local item = scope(key)
  item.epoch = item.epoch + 1
  item.inflight = true
  return item.epoch
end

function M.finish(key, token)
  local item = scope(key)
  if item.epoch == token then
    item.inflight = false
  end
end

function M.current(key, token)
  return scope(key).epoch == token
end

function M.invalidate(key)
  local item = scope(key)
  item.epoch = item.epoch + 1
  item.inflight = false
end

function M.inflight(key)
  return scope(key).inflight == true
end

function M.decode_json(result)
  if result.code ~= 0 then
    return false, nil, command_failure(result)
  end
  local ok, data = pcall(vim.json.decode, result.stdout or '[]')
  if ok then
    return true, data
  end
  return false, nil, decode_failure(result, data)
end

---@param failure forge.PickerSessionFailure?
---@param fallback string
---@return string
function M.failure_message(failure, fallback)
  local message = type(failure) == 'table' and trim(failure.message) or nil
  return message or fallback
end

function M.prefetch_json(opts)
  if opts.skip_if and opts.skip_if() then
    return false
  end
  if M.inflight(opts.key) then
    return false
  end
  request_json(opts.key, opts.cmd, function(ok, data, result, stale)
    if stale then
      return
    end
    if ok then
      if opts.on_success then
        opts.on_success(data)
      end
    elseif opts.on_failure then
      opts.on_failure(result)
    end
  end)
  return true
end

function M.pick_json(opts)
  local picker = require('forge.picker')

  local function handle_success(data, emit)
    if opts.on_success then
      opts.on_success(data)
    end
    if emit then
      local entries = opts.build_entries(data)
      emit_entries(emit, entries)
    else
      opts.open(data)
    end
  end

  local function handle_failure(result, emit)
    if opts.on_failure then
      opts.on_failure(result)
    end
    if emit then
      local entry = opts.error_entry and opts.error_entry(result) or nil
      if entry then
        emit(entry)
      end
      emit(nil)
    end
  end

  local function request(emit)
    if opts.on_fetch then
      opts.on_fetch()
    end
    request_json(opts.key, opts.cmd, function(ok, data, result, stale)
      if stale then
        if emit then
          emit(nil)
        end
        return
      end
      if ok then
        handle_success(data, emit)
      else
        handle_failure(result, emit)
      end
    end)
  end

  if opts.cached then
    opts.open(opts.cached)
    return
  end

  picker.pick({
    prompt = resolve(opts.loading_prompt) or '',
    entries = {},
    actions = opts.actions,
    header_order = opts.header_order,
    picker_name = opts.picker_name,
    back = opts.back,
    stream = opts.stream or function(emit)
      request(emit)
    end,
  })
end

return M
