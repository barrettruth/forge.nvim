--- forge.nvim public API.
---
--- There is no setup(). Loading the plugin is enough.
local M = {}

--- Open an issue, or the issue list. See |:Issue| for accepted targets.
--- @param target string?
function M.issue(target)
  require('forge.issue').open(target)
end

return M
