local log = require('forge.log')

--- Absent rather than `vim.NIL`, which is userdata and reads as present.
--- Objects only: a null dropped from a list leaves a hole `ipairs` stops at.
local DECODE = { luanil = { object = true } }

local M = {}

--- A request to make of github.
--- @class forge.Request
--- @field desc string? what to say while it is in flight
--- @field query string
--- @field variables table<string, string|integer|string[]>
--- @field cwd string? where to run gh, which is where it resolves the repository

--- The owner and repo to send for a target.
---
--- A target that named no repository is sent as gh's own `{owner}`/`{repo}`
--- placeholders. gh expands those to the base repository, where a fork's
--- issues and pull requests live. It honours `gh repo set-default` doing it.
--- Working it out from a remote here is how a fork ends up answered for by
--- the wrong repository.
--- @param t forge.Target
--- @return string owner
--- @return string repo
function M.slug(t)
  local owner, repo = (t.project or ''):match('^([^/]+)/([^/]+)$')
  return owner or '{owner}', repo or '{repo}'
end

local SLUG = { owner = true, repo = true }

--- How to pass one variable to `gh api`.
---
--- `--raw-field` is the safe default. It sends a String and cannot retype it,
--- keeping a repository named "123" a name. It does not read a leading "@" as
--- a filename the way `--field` does. But gh expands `{owner}` and `{repo}`
--- only in `--field`, and only `--field` can carry a number.
--- @param name string
--- @param value string|integer
--- @return '-f'|'-F'
local function flag(name, value)
  if type(value) == 'number' then
    return '-F'
  end
  return (SLUG[name] and value:match('^{%a+}$')) and '-F' or '-f'
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
      cmd[#cmd + 1] = flag(name, value)
      cmd[#cmd + 1] = ('%s=%s'):format(name, value)
    end
  end
end

--- Send a GraphQL document through the gh CLI.
---
--- Owns the progress message for the request. Every path out of here ends it.
--- Errors are reported, never raised.
--- @param req forge.Request
--- @param on_done fun(data: table)
--- @param on_fail fun()? for a caller to stop saying it is working
function M.graphql(req, on_done, on_fail)
  local desc, variables = req.desc, req.variables
  local cmd = { 'gh', 'api', 'graphql', '-f', 'query=' .. req.query }
  fields(cmd, variables)

  local done = desc and log.progress(desc) or function() end

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
      local ok, body = pcall(vim.json.decode, out.stdout, DECODE)
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
--- REST rather than GraphQL. A mutation wants a repository's node id, another
--- round trip. REST takes the owner and repo already in hand.
--- @class forge.Rest
--- @field desc string what to say while it is in flight
--- @field method 'POST'|'PATCH'
--- @field path string
--- @field variables table<string, string|integer|string[]>
--- @field cwd string?

--- @param req forge.Rest
--- @param on_done fun(data: table)
--- @param on_fail fun()? for a caller to keep something unsaved
function M.rest(req, on_done, on_fail)
  local cmd = { 'gh', 'api', '--method', req.method, req.path }
  fields(cmd, req.variables)

  local done = log.progress(req.desc)

  vim.system(cmd, { text = true, cwd = req.cwd }, function(out)
    vim.schedule(function()
      local ok, body = pcall(vim.json.decode, out.stdout, DECODE)
      if out.code ~= 0 then
        -- github puts a generic sentence in `message` and the actual reason
        -- inside `errors`. The reason wins where there is one.
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
