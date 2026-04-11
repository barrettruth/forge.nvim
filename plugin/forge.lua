vim.api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function()
    local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    local items = info.loclist == 1 and vim.fn.getloclist(0) or vim.fn.getqflist()
    if #items == 0 then
      return
    end
    local bufname = vim.fn.bufname(items[1].bufnr)
    if not bufname:match('^diffs://') then
      return
    end
    vim.fn.matchadd('DiffAdd', [[\v\+\d+]])
    vim.fn.matchadd('DiffDelete', [[\v-\d+]])
    vim.fn.matchadd('DiffChange', [[\v\s\zsM\ze\s]])
    vim.fn.matchadd('diffAdded', [[\v\s\zsA\ze\s]])
    vim.fn.matchadd('DiffDelete', [[\v\s\zsD\ze\s]])
    vim.fn.matchadd('DiffText', [[\v\s\zsR\ze\s]])
  end,
})

local function set_plug(mode, lhs, rhs)
  vim.keymap.set(mode, ('<Plug>(%s)'):format(lhs), rhs)
end

local function open_route(route)
  return function()
    require('forge').open(route)
  end
end

set_plug('n', 'forge', open_route(nil))

for _, spec in ipairs({
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
  { 'n', 'forge-prs', 'prs' },
  { 'n', 'forge-issues', 'issues' },
  { 'n', 'forge-ci', 'ci' },
  { { 'n', 'x' }, 'forge-browse', 'browse' },
  { 'n', 'forge-releases', 'releases' },
  { 'n', 'forge-branches', 'branches' },
  { 'n', 'forge-commits', 'commits' },
  { 'n', 'forge-worktrees', 'worktrees' },
}) do
  set_plug(spec[1], spec[2], open_route(spec[3]))
end

set_plug('n', 'forge-review-toggle', function()
  require('forge.review').toggle()
end)

set_plug('n', 'forge-review-end', function()
  require('forge.review').stop()
end)

set_plug('n', 'forge-review-files', function()
  require('forge.review').files()
end)

set_plug('n', 'forge-review-next-file', function()
  require('forge.review').next_file()
end)

set_plug('n', 'forge-review-prev-file', function()
  require('forge.review').prev_file()
end)

set_plug('n', 'forge-review-next-hunk', function()
  require('forge.review').next_hunk()
end)

set_plug('n', 'forge-review-prev-hunk', function()
  require('forge.review').prev_hunk()
end)

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
