local M = {}

local state = {}

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
  local ok, data = pcall(vim.json.decode, result.stdout or '[]')
  if result.code == 0 and ok and data then
    return true, data
  end
  return false, nil
end

function M.prefetch_json(opts)
  if opts.skip_if and opts.skip_if() then
    return false
  end
  if M.inflight(opts.key) then
    return false
  end
  local token = M.begin(opts.key)
  vim.system(resolve(opts.cmd), { text = true }, function(result)
    vim.schedule(function()
      M.finish(opts.key, token)
      if not M.current(opts.key, token) then
        return
      end
      local ok, data = M.decode_json(result)
      if ok then
        if opts.on_success then
          opts.on_success(data)
        end
      elseif opts.on_failure then
        opts.on_failure(result)
      end
    end)
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
    local token = M.begin(opts.key)
    vim.system(resolve(opts.cmd), { text = true }, function(result)
      vim.schedule(function()
        M.finish(opts.key, token)
        if not M.current(opts.key, token) then
          if emit then
            emit(nil)
          end
          return
        end
        local ok, data = M.decode_json(result)
        if ok then
          handle_success(data, emit)
        else
          handle_failure(result, emit)
        end
      end)
    end)
  end

  if opts.cached then
    opts.open(opts.cached)
    return
  end

  if picker.backend() == 'fzf-lua' then
    picker.pick({
      prompt = resolve(opts.loading_prompt) or '',
      entries = {},
      actions = opts.actions,
      picker_name = opts.picker_name,
      stream = function(emit)
        request(emit)
      end,
    })
    return
  end

  request(nil)
end

return M
