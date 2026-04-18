local M = {}

local function get_debug()
  local cfg = vim.g.forge
  return cfg and cfg.debug
end

local function log_to_file(level_name, msg)
  local dbg = get_debug()
  if type(dbg) ~= 'string' then
    return
  end
  local fd = io.open(dbg, 'a')
  if fd then
    fd:write(os.date('%H:%M:%S') .. ' [' .. level_name .. '] ' .. msg .. '\n')
    fd:close()
  end
end

local function notify(msg, level)
  local run = function()
    vim.cmd.redraw()
    vim.notify('[forge]: ' .. msg, level)
  end
  if vim.in_fast_event() then
    vim.schedule(run)
    return
  end
  run()
end

function M.debug(msg)
  local dbg = get_debug()
  if not dbg then
    return
  end
  log_to_file('DEBUG', msg)
  if type(dbg) ~= 'string' then
    notify(msg, vim.log.levels.DEBUG)
  end
end

function M.info(msg)
  log_to_file('INFO', msg)
  notify(msg, vim.log.levels.INFO)
end

function M.warn(msg)
  log_to_file('WARN', msg)
  notify(msg, vim.log.levels.WARN)
end

function M.error(msg)
  log_to_file('ERROR', msg)
  notify(msg, vim.log.levels.ERROR)
end

return M
