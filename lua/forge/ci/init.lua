local M = {}

local function status_text(run)
  if type(run) == 'table' then
    run = run.status
  end
  if type(run) ~= 'string' then
    return ''
  end
  return vim.trim(run):lower()
end

function M.in_progress(run)
  local status = status_text(run)
  return status == 'in_progress' or status == 'queued' or status == 'pending' or status == 'running'
end

function M.toggle_verb(run)
  local status = status_text(run)
  if status == 'skipped' then
    return nil
  end
  if M.in_progress(status) then
    return 'cancel'
  end
  return 'rerun'
end

return M
