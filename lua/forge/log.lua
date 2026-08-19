local M = {}

local PREFIX = '[forge]: '

--- @param msg string
function M.info(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.INFO)
end

--- @param msg string
function M.warn(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.WARN)
end

--- Report a failure. The only way forge reports one. Nothing raises out of a
--- callback. An unreachable remote never surfaces as a Lua traceback.
--- @param msg string
function M.err(msg)
  vim.schedule(function()
    vim.notify(PREFIX .. msg, vim.log.levels.ERROR)
  end)
end

--- Announce that something is in flight, and return how to end it.
---
--- Progress goes out of band. A buffer never renders placeholder text. The
--- returned function must be called. A message left `running` dangles forever
--- for anything tracking it by id.
--- @param msg string
--- @return fun(status: 'success'|'failed'|'cancel', done: string?)
function M.progress(msg)
  local progress = { kind = 'progress', source = 'forge', title = 'forge', status = 'running' }
  progress.id = vim.api.nvim_echo({ { msg } }, false, progress)

  return function(status, done)
    progress.status = status
    vim.api.nvim_echo({ { done or msg } }, false, progress)
  end
end

return M
