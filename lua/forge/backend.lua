--- Which forge answers for b host. Everything above this asks by hostname and
--- is told nothing more; see |forge.Backend| for what it gets back.

local log = require('forge.log')

local M = {}

--- The forge a view that never named one belongs to, as forge.uri spells it.
local DEFAULT = 'github.com'

--- The backend answering for `host`, or nothing, having said why.
---
--- github.com and the hosts under it, and nothing else: a github an
--- organisation installs itself cannot be told from a gitlab by its hostname,
--- and there is nowhere to be told which it is. ci.nvim draws the line in the
--- same place. A host with no backend is named here rather than guessed at,
--- since the wrong one fails at the first request with an error about the
--- request instead.
--- @param host string? absent for a target no forge has answered yet
--- @return forge.Backend?
function M.of(host)
  host = host or DEFAULT
  if host == DEFAULT or host:match('%.github%.com$') then
    return require('forge.github')
  end
  log.err(('no backend for %s'):format(host))
end

return M
