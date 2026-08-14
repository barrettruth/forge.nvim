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

--- Report a failure.
---
--- The only way forge reports a failure. Nothing raises out of a callback, so
--- an unreachable remote never reaches the user as a Lua traceback.
--- @param msg string
function M.err(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.ERROR)
end

--- Announce that something is in flight, and return how to end it.
---
--- Progress is out of band, so a buffer never renders placeholder text. The
--- returned function must be called: a progress message left in the `running`
--- state dangles forever for anything tracking it by id.
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
