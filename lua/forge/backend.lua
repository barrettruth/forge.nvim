--- Which forge answers for a host. Everything above this asks by hostname and
--- is told nothing more. See |forge.Backend| for what it gets back.

local M = {}

--- The forge a view that never named one belongs to, as forge.uri spells it.
local DEFAULT = 'github.com'

--- Where each CLI keeps the hosts it has been logged in to.
local LOGINS = {
  {
    cli = 'glab',
    dir = 'GLAB_CONFIG_DIR',
    path = { 'glab-cli', 'config.yml' },
    -- glab nests its hosts under a `hosts:` key where gh does not. Find the
    -- section before reading its keys.
    section = 'hosts:',
  },
  { cli = 'gh', dir = 'GH_CONFIG_DIR', path = { 'gh', 'hosts.yml' } },
}

--- @type table<string, string>?
local logins

--- Every host either CLI holds a login for.
---
--- Read off disk, not asked for. `glab auth status` is a round trip on a path
--- that has to answer before a keystroke is drawn. A self-hosted gitlab and a
--- self-hosted github cannot be told apart by hostname. A login is the one
--- place the answer is already written down.
--- @return table<string, string>
local function known()
  if logins then
    return logins
  end
  logins = {}
  for _, it in ipairs(LOGINS) do
    local base = vim.env[it.dir] or vim.fs.joinpath(vim.fn.stdpath('config') --[[@as string]], '..')
    local file = vim.fs.joinpath(base, unpack(it.path))
    local lines = vim.fn.filereadable(file) == 1 and vim.fn.readfile(file) or {}
    local within = not it.section
    for _, line in ipairs(lines) do
      if it.section and line:find('^' .. it.section) then
        within = true
      elseif within then
        local host = line:match('^%s*([%w][%w.-]*):%s*$')
        -- A key one level deeper than the section is a host. Anything deeper
        -- is that host's own settings.
        if host and (not it.section or line:match('^%s+')) then
          logins[host] = logins[host] or it.cli
        elseif it.section and line:match('^%S') then
          within = false
        end
      end
    end
  end
  return logins
end

--- How long to let git answer where the remote points. It reads a local
--- config file. Anything slower will not answer at all.
local GIT = 2000

--- @type table<string, string>
local remotes = {}

--- The host the checkout at `cwd` pushes to.
---
--- A target naming no repository names no forge either. Which CLI to send it
--- to has to be settled before the request. `upstream` before `origin`, as
--- ci.nvim does. Choosing the CLI from one remote while the CLI reads another
--- is how a fork gets answered for by the wrong forge.
--- @param cwd string?
--- @return string?
function M.here(cwd)
  local at = cwd or vim.uv.cwd() or '.'
  if remotes[at] ~= nil then
    return remotes[at] ~= '' and remotes[at] or nil
  end
  local found = ''
  for _, name in ipairs({ 'upstream', 'origin' }) do
    local r = vim.system({ 'git', 'remote', 'get-url', name }, { text = true, cwd = at }):wait(GIT)
    local url = r.code == 0 and vim.trim(r.stdout or '') or ''
    if url ~= '' then
      local authority = url:match('^%a[%w+.-]*://([^/]+)') or url:match('^([^/]+):')
      found = authority and (authority:gsub('^[^@]*@', ''):gsub(':%d+$', '')) or ''
      break
    end
  end
  remotes[at] = found
  return found ~= '' and found or nil
end

--- @param host string
--- @return boolean
local function github(host)
  return host == DEFAULT or host:match('%.github%.com$') ~= nil
end

--- @param host string
--- @return boolean
local function gitlab(host)
  return host == 'gitlab.com' or host:match('%.gitlab%.com$') ~= nil
end

--- The backend answering for `host`, and the host it settled on.
---
--- The two known names first, then whichever CLI holds a login, then github.
--- An enterprise install answers to `gh` without ever naming itself github.
--- A host no backend can place fails at its first request with the forge's own
--- error, not one invented here. ci.nvim falls back to Forgejo here.
--- @param host string? absent for a target no forge has answered yet
--- @param cwd string? the checkout to read a host from, when the target has none
--- @return forge.Backend
--- @return string host the one it chose
function M.of(host, cwd)
  host = host or M.here(cwd) or DEFAULT
  if gitlab(host) or (not github(host) and known()[host] == 'glab') then
    return require('forge.glab'), host
  end
  return require('forge.github'), host
end

--- Forget the logins read from disk. A login made since is picked up.
function M.reload()
  logins = nil
end

return M
