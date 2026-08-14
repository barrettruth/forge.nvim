--- forge.nvim public API.
---
--- There is no setup(). Loading the plugin is enough.
local M = {}

--- Open an issue, or the issue list. See |:Issue| for accepted targets.
--- @param target string?
function M.issue(target)
  require('forge.issue').open(target)
end

--- Open a pull request, or the pull request list. See |:PR| for accepted
--- targets.
--- @param target string?
function M.pr(target)
  require('forge.pr').open(target)
end

return M
