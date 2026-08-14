local log = require('forge.log')

local M = {}

--- Send a GraphQL document through the gh CLI.
---
--- Owns the progress message for the request, so every path out of here ends it
--- and none can dangle. Variables are typed by their Lua type: numbers become
--- GraphQL Ints, anything else a String. Errors are reported, never raised.
--- @param desc string what to say while the request is in flight
--- @param query string
--- @param variables table<string, string|integer>
--- @param on_done fun(data: table)
function M.graphql(desc, query, variables, on_done)
  local cmd = { 'gh', 'api', 'graphql', '-f', 'query=' .. query }
  for name, value in pairs(variables) do
    cmd[#cmd + 1] = type(value) == 'number' and '-F' or '-f'
    cmd[#cmd + 1] = ('%s=%s'):format(name, value)
  end

  local done = log.progress(desc)

  vim.system(cmd, { text = true }, function(out)
    vim.schedule(function()
      local function fail(msg)
        done('failed', msg)
        log.err(msg)
      end

      if out.code ~= 0 then
        local stderr = vim.trim(out.stderr or '')
        return fail(stderr ~= '' and stderr or 'gh api graphql failed')
      end
      local ok, body = pcall(vim.json.decode, out.stdout)
      if not ok or type(body) ~= 'table' then
        return fail('could not read gh output')
      end
      if body.errors and body.errors[1] then
        return fail(body.errors[1].message or 'graphql error')
      end

      done('success', desc)
      on_done(body.data or {})
    end)
  end)
end

--- Warn when a connection came back truncated.
---
--- Every connection is capped. Asking for totalCount alongside the nodes is
--- what makes the cap visible instead of silently losing the tail.
--- @param connection table?
--- @param what string
function M.check_truncated(connection, what)
  if not connection then
    return
  end
  local shown = #(connection.nodes or {})
  local total = connection.totalCount or shown
  if total > shown then
    log.warn(('showing %d of %d %s'):format(shown, total, what))
  end
end

return M
