--- Which forge answers for a host. Everything above this asks by hostname and
--- is told nothing more; see |forge.Backend| for what it gets back.

local M = {}

--- The forge a view that never named one belongs to, as forge.uri spells it.
local DEFAULT = 'github.com'

--- Where each CLI keeps the hosts it has been logged in to, under $XDG or the
--- variable it reads first.
local LOGINS = {
  {
    cli = 'glab',
    dir = 'GLAB_CONFIG_DIR',
    path = { 'glab-cli', 'config.yml' },
    --- Nested under a `hosts:` key, unlike gh's, so the section has to be
    --- found before its keys mean anything.
    section = 'hosts:',
  },
  { cli = 'gh', dir = 'GH_CONFIG_DIR', path = { 'gh', 'hosts.yml' } },
}

--- @type table<string, string>?
local logins

--- Every host either CLI holds a login for.
---
--- Read rather than asked for: `glab auth status` is a round trip on a path
--- that has to answer before a keystroke is drawn, and the file it would
--- consult is right here. A hostname alone cannot tell a gitlab an
--- organisation installs itself from a github it installs itself, and a login
--- is the one place the answer is already written down.
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
        --- A key one level deeper than the section is a host; anything deeper
        --- is that host's own settings.
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

--- How long to let git answer where the remote points. It is a local read of
--- a config file; anything slower than this is a repository that is not going
--- to answer at all.
local GIT = 2000

--- @type table<string, string>
local remotes = {}

--- The host the checkout at `cwd` pushes to.
---
--- A target naming no repository names no forge either, and the CLI it should
--- be sent to has to be settled before the request rather than after it. `gh`
--- and `glab` each work this out from the same remotes, so reading them here
--- reaches the same answer. ci.nvim prefers `upstream` over `origin` for the
--- same reason it does: choosing the CLI from one remote while it reads
--- another is how a fork is answered for by the wrong forge.
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

--- The backend answering for `host`.
---
--- The two names first, then whichever CLI holds a login for the host, and
--- github for anything left: an enterprise install answers to `gh` without
--- ever naming itself github, and a host no backend can place fails at its
--- first request with the forge's own error, which says more than one invented
--- here. ci.nvim assumes Forgejo in the same position and for the same reason.
--- The host is answered alongside the backend because a view that named none
--- is still filed under one, and the checkout is the only thing that knew.
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

--- Forget the logins read from disk, so a login made since is picked up.
function M.reload()
  logins = nil
end

return M
