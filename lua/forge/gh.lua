local log = require('forge.log')

local M = {}

--- A request to make of github.
--- @class forge.Request
--- @field desc string what to say while it is in flight
--- @field query string
--- @field variables table<string, string|integer|string[]>
--- @field cwd string? where to run gh, which is where it resolves the repository

--- The owner and repo to send for a target.
---
--- A target that named no repository is sent as gh's own `{owner}`/`{repo}`
--- placeholders, which gh expands to the *base* repository: the one a fork's
--- issues and pull requests actually live on, honouring `gh repo set-default`
--- as it goes. Working that out from a remote here instead is exactly how a
--- fork ends up answered for by the wrong repository.
--- @param t forge.Target
--- @return string owner
--- @return string repo
function M.slug(t)
  return t.owner or '{owner}', t.repo or '{repo}'
end

--- How to pass one variable to `gh api`.
---
--- `--raw-field` is the safe default: it sends a String and cannot retype it,
--- so a repository named "123" stays a name. gh only expands `{owner}` and
--- `{repo}` in `--field` though, and only that flag can carry a number, so
--- those two get it instead.
--- @param value string|integer
--- @return '-f'|'-F'
local function flag(value)
  if type(value) == 'number' or tostring(value):find('{%a+}') then
    return '-F'
  end
  return '-f'
end

--- Both kinds of request carry their variables the same way.
--- @param cmd string[]
--- @param variables table<string, string|integer|string[]>
local function fields(cmd, variables)
  for name, value in pairs(variables or {}) do
    if type(value) == 'table' then
      for _, item in ipairs(value) do
        cmd[#cmd + 1] = '-f'
        cmd[#cmd + 1] = ('%s[]=%s'):format(name, item)
      end
    else
      cmd[#cmd + 1] = flag(value)
      cmd[#cmd + 1] = ('%s=%s'):format(name, value)
    end
  end
end

--- Send a GraphQL document through the gh CLI.
---
--- Owns the progress message for the request, so every path out of here ends
--- it and none can dangle. Errors are reported, never raised.
--- @param req forge.Request
--- @param on_done fun(data: table)
--- @param on_fail fun()? so a caller that said it was working can stop saying it
function M.graphql(req, on_done, on_fail)
  local desc, variables = req.desc, req.variables
  local cmd = { 'gh', 'api', 'graphql', '-f', 'query=' .. req.query }
  fields(cmd, variables)

  local done = log.progress(desc)

  vim.system(cmd, { text = true, cwd = req.cwd }, function(out)
    vim.schedule(function()
      local function fail(msg)
        done('failed', msg)
        log.err(msg)
        if on_fail then
          on_fail()
        end
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

--- Ask github's REST API to make something.
---
--- Creating goes through REST rather than GraphQL because a mutation wants a
--- repository's node id, which is a round trip to learn, while REST takes the
--- owner and repo we already have and label *names* rather than their ids.
--- Github answers a refused write with a generic `message` and the reason
--- itself inside `errors`, so the reason is preferred where there is one.
--- @class forge.Rest
--- @field desc string what to say while it is in flight
--- @field method 'POST'|'PATCH'
--- @field path string
--- @field variables table<string, string|integer|string[]>
--- @field cwd string?

--- @param req forge.Rest
--- @param on_done fun(data: table)
--- @param on_fail fun()? so a caller holding something unsaved can keep it
function M.rest(req, on_done, on_fail)
  local cmd = { 'gh', 'api', '--method', req.method, req.path }
  fields(cmd, req.variables)

  local done = log.progress(req.desc)

  vim.system(cmd, { text = true, cwd = req.cwd }, function(out)
    vim.schedule(function()
      local ok, body = pcall(vim.json.decode, out.stdout)
      if out.code ~= 0 then
        local message = nil
        if ok and type(body) == 'table' then
          local first = body.errors and body.errors[1]
          message = (type(first) == 'table' and first.message) or body.message
        end
        local msg = message or vim.trim(out.stderr or '')
        msg = msg ~= '' and msg or 'gh api failed'
        done('failed', msg)
        log.err(msg)
        if on_fail then
          on_fail()
        end
        return
      end
      if not ok or type(body) ~= 'table' then
        done('failed', 'could not read gh output')
        log.err('could not read gh output')
        if on_fail then
          on_fail()
        end
        return
      end
      done('success', req.desc)
      on_done(body)
    end)
  end)
end

return M
