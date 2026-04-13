local function set_plug(mode, lhs, rhs)
  vim.keymap.set(mode, ('<Plug>(%s)'):format(lhs), rhs)
end

local function open_route(route)
  return function()
    require('forge').open(route)
  end
end

local section_plugs = {
  { 'n', 'forge-prs', 'prs' },
  { 'n', 'forge-issues', 'issues' },
  { 'n', 'forge-ci', 'ci' },
  { { 'n', 'x' }, 'forge-browse', 'browse' },
  { 'n', 'forge-releases', 'releases' },
  { 'n', 'forge-branches', 'branches' },
  { 'n', 'forge-commits', 'commits' },
  { 'n', 'forge-worktrees', 'worktrees' },
}

local exact_route_plugs = {
  { 'n', 'forge-prs-open', 'prs.open' },
  { 'n', 'forge-prs-closed', 'prs.closed' },
  { 'n', 'forge-prs-all', 'prs.all' },
  { 'n', 'forge-issues-open', 'issues.open' },
  { 'n', 'forge-issues-closed', 'issues.closed' },
  { 'n', 'forge-issues-all', 'issues.all' },
  { 'n', 'forge-ci-current-branch', 'ci.current_branch' },
  { 'n', 'forge-ci-all', 'ci.all' },
  { { 'n', 'x' }, 'forge-browse-contextual', 'browse.contextual' },
  { 'n', 'forge-browse-branch', 'browse.branch' },
  { 'n', 'forge-browse-commit', 'browse.commit' },
  { 'n', 'forge-releases-all', 'releases.all' },
  { 'n', 'forge-releases-draft', 'releases.draft' },
  { 'n', 'forge-releases-prerelease', 'releases.prerelease' },
  { 'n', 'forge-branches-local', 'branches.local' },
  { 'n', 'forge-commits-current-branch', 'commits.current_branch' },
  { 'n', 'forge-worktrees-list', 'worktrees.list' },
}

set_plug('n', 'forge', open_route(nil))

for _, spec in ipairs(section_plugs) do
  set_plug(spec[1], spec[2], open_route(spec[3]))
end

for _, spec in ipairs(exact_route_plugs) do
  set_plug(spec[1], spec[2], open_route(spec[3]))
end

vim.api.nvim_create_user_command('Forge', function(opts)
  require('forge.cmd').run(opts)
end, {
  bang = true,
  nargs = '*',
  complete = function(arglead, cmdline, cursorpos)
    return require('forge.cmd').complete(arglead, cmdline, cursorpos)
  end,
  desc = 'forge.nvim',
})
