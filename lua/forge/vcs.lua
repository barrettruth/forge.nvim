local log = require('forge.log')

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

--- The directory a request is made from: the buffer's own where it has a file
--- behind it, else the working directory.
--- @return string
function M.dir()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' or name:find('^%w[%w+.-]*://') then
    return vim.fn.getcwd()
  end
  return vim.fs.dirname(name)
end

--- @param dir string
--- @return string?
function M.git_dir(dir)
  return run(dir, { 'git', 'rev-parse', '--absolute-git-dir' })
end

--- Bring a pull request into this repository, without disturbing it.
---
--- The base branch comes too. A merge base needs both ends. By URL, not by
--- remote name. The repository a pull request belongs to is not always the one
--- `origin` points at, and in a fork never is. The refs land under
--- `refs/forge/`. No branch, tag or working tree is touched.
--- @param dir string
--- @param url string
--- @param number integer
--- @param base string
--- @param ref string what the forge publishes the head as
--- @param sigil string what the forge writes in front of a number
--- @param on_done fun(base: string, head: string)
function M.fetch_pull(dir, url, number, base, ref, sigil, on_done)
  local head_ref = ('refs/forge/%d/head'):format(number)
  local base_ref = ('refs/forge/%d/base'):format(number)
  local cmd = {
    'git',
    'fetch',
    '--quiet',
    url,
    ('+%s:%s'):format(ref, head_ref),
    ('+refs/heads/%s:%s'):format(base, base_ref),
  }

  local done = log.progress(('fetching %s%d'):format(sigil, number))
  vim.system(cmd, { cwd = dir, text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        local why = vim.trim((out.stderr or ''):gsub('\n.*', ''))
        why = why ~= '' and why or 'git fetch failed'
        done('failed', why)
        return log.err(why)
      end
      done('success', ('fetched %s%d'):format(sigil, number))
      on_done(base_ref, head_ref)
    end)
  end)
end

--- The branch whose pull request a bare |:PR| means.
---
--- git answers first. A colocated jj repository leaves git's HEAD detached at
--- `@-`, one commit *behind* the bookmark naming the pull request. git there
--- is wrong, not merely silent. `--ignore-working-copy` keeps reading a branch
--- from writing to the repository.
---
--- jj has no current branch, only bookmarks on changes. The answer is the
--- bookmark on `@`, or on `@-` where `@` is the empty commit jj leaves on top.
--- A change wearing none is reported, not guessed at. The nearest bookmark
--- below belongs to another change, and would propose its branch.
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

  local function ask(revision, template)
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

  local revision = ask('@', 'if(empty, "empty", "work")') == 'empty' and '@-' or '@'
  local marks = ask(revision, 'bookmarks')
  local nearest = marks and vim.split(marks, '%s+')[1]
  if not nearest or nearest == '' then
    return nil, 'this change has no bookmark, so there is no branch to propose'
  end

  local name = nearest:gsub('%*$', '')
  if name ~= nearest then
    return nil, ('%s is not pushed, so no forge can see it'):format(name)
  end
  return name
end

return M
