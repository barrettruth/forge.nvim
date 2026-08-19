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
--- @param host string? absent for a target no forge has answered yet
--- @return forge.Backend
function M.of(host)
  host = host or DEFAULT
  if gitlab(host) then
    return require('forge.glab')
  end
  if not github(host) and known()[host] == 'glab' then
    return require('forge.glab')
  end
  return require('forge.github')
end

--- Forget the logins read from disk, so a login made since is picked up.
function M.reload()
  logins = nil
end

return M
