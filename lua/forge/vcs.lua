local M = {}

local TIMEOUT = 2000

--- @param dir string
--- @param cmd string[]
--- @return string?
local function run(dir, cmd)
  local out = vim.system(cmd, { cwd = dir, text = true }):wait(TIMEOUT)
  if out.code ~= 0 then
    return nil
  end
  local text = vim.trim(out.stdout or '')
  return text ~= '' and text or nil
end

--- The directory a request is made from.
---
--- The buffer's own, when it has a file behind it, so a file opened from
--- another repository is asked about there rather than wherever nvim was
--- started. A buffer with no file, forge's own included, falls back to the
--- working directory.
--- @return string
function M.dir()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' or name:find('^%w[%w+.-]*://') then
    return vim.fn.getcwd()
  end
  return vim.fs.dirname(name)
end

--- A branch as this checkout can name it, if it can.
---
--- A pull request names branches as github holds them, and a checkout may
--- have the same branch locally, only as a remote-tracking ref, or not at
--- all. The first that resolves is the one to hand on.
--- @param dir string
--- @param branch string
--- @return string?
function M.rev(dir, branch)
  for _, name in ipairs({ branch, 'origin/' .. branch }) do
    if run(dir, { 'git', 'rev-parse', '--verify', '--quiet', name .. '^{commit}' }) then
      return name
    end
  end
end

--- The branch whose pull request a bare |:PR| means.
---
--- git answers first. A colocated jj repository leaves git's HEAD detached at
--- `@-`, one commit *behind* the bookmark that names the pull request, so git
--- there is not merely silent but wrong, and jj is asked instead. The working
--- copy is not snapshotted: reading a branch must not write to the repository.
---
--- jj has no current branch. A bookmark belongs to a change, so the answer is
--- the bookmark on the change being worked on: `@`, unless `@` is the empty
--- commit jj leaves on top, in which case `@-`. A change wearing no bookmark
--- is reported rather than guessed at, because the nearest one below belongs
--- to a different change and would propose someone else's branch.
--- @param dir string
--- @return string? branch
--- @return string? err
function M.branch(dir)
  local head = run(dir, { 'git', 'symbolic-ref', '--short', 'HEAD' })
  if head then
    return head
  end

  if vim.fn.executable('jj') ~= 1 then
    return nil, 'no branch here, so no pull request to open'
  end

  local function log(revision, template)
    return run(dir, {
      'jj',
      'log',
      '--no-graph',
      '--ignore-working-copy',
      '--revisions',
      revision,
      '--template',
      template,
    })
  end

  local revision = log('@', 'if(empty, "empty", "work")') == 'empty' and '@-' or '@'
  local marks = log(revision, 'bookmarks')
  local nearest = marks and vim.split(marks, '%s+')[1]
  if not nearest or nearest == '' then
    return nil, 'this change has no bookmark, so there is no branch to propose'
  end

  local name = nearest:gsub('%*$', '')
  if name ~= nearest then
    return nil, ('%s is not pushed, so github cannot see it'):format(name)
  end
  return name
end

return M
