vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(_, text)
      return text
    end,
  }
end

describe('github', function()
  local gh = require('forge.github')

  it('has correct metadata', function()
    assert.equals('gh', gh.cli)
    assert.equals('github', gh.name)
    assert.equals('pr', gh.kinds.pr)
    assert.equals('issue', gh.kinds.issue)
  end)

  it('builds list_pr_json_cmd', function()
    local cmd = gh:list_pr_json_cmd('open')
    assert.equals('gh', cmd[1])
    assert.truthy(vim.tbl_contains(cmd, '--state'))
    assert.truthy(vim.tbl_contains(cmd, 'open'))
    assert.truthy(vim.tbl_contains(cmd, '--json'))
  end)

  it('respects explicit PR list limits', function()
    local cmd = gh:list_pr_json_cmd('open', 55)
    assert.truthy(vim.tbl_contains(cmd, '--limit'))
    assert.truthy(vim.tbl_contains(cmd, '55'))
  end)

  it('builds merge_cmd with method flag', function()
    local squash = gh:merge_cmd('42', 'squash')
    assert.same({ 'gh', 'pr', 'merge', '42', '--squash' }, vim.list_slice(squash, 1, 5))
    assert.truthy(vim.tbl_contains(squash, '-R'))

    local rebase = gh:merge_cmd('10', 'rebase')
    assert.same({ 'gh', 'pr', 'merge', '10', '--rebase' }, vim.list_slice(rebase, 1, 5))
    assert.truthy(vim.tbl_contains(rebase, '-R'))
  end)

  it('builds merge_cmd without a method flag', function()
    local cmd = gh:merge_cmd('42')
    assert.same({ 'gh', 'pr', 'merge', '42' }, vim.list_slice(cmd, 1, 4))
    assert.truthy(vim.tbl_contains(cmd, '-R'))
    assert.falsy(vim.tbl_contains(cmd, '--merge'))
    assert.falsy(vim.tbl_contains(cmd, '--squash'))
    assert.falsy(vim.tbl_contains(cmd, '--rebase'))
  end)

  it('builds create_pr_cmd', function()
    local cmd = gh:create_pr_cmd('title', 'body', 'main', false, nil)
    assert.truthy(vim.tbl_contains(cmd, '--title'))
    assert.truthy(vim.tbl_contains(cmd, '--base'))
    assert.falsy(vim.tbl_contains(cmd, '--draft'))
  end)

  it('adds draft flag to create_pr_cmd', function()
    assert.truthy(vim.tbl_contains(gh:create_pr_cmd('t', 'b', 'main', true, nil), '--draft'))
  end)

  it('adds reviewers to create_pr_cmd', function()
    local cmd = gh:create_pr_cmd('t', 'b', 'main', false, { 'alice', 'bob' })
    local count = 0
    for _, v in ipairs(cmd) do
      if v == '--reviewer' then
        count = count + 1
      end
    end
    assert.equals(2, count)
  end)

  it('builds checkout_cmd', function()
    local cmd = gh:checkout_cmd('5')
    assert.same({ 'gh', 'pr', 'checkout', '5' }, vim.list_slice(cmd, 1, 4))
    assert.truthy(vim.tbl_contains(cmd, '-R'))
  end)

  it('builds close/reopen commands', function()
    local close = gh:close_cmd('3')
    assert.same({ 'gh', 'pr', 'close', '3' }, vim.list_slice(close, 1, 4))
    assert.truthy(vim.tbl_contains(close, '-R'))

    local reopen = gh:reopen_cmd('3')
    assert.same({ 'gh', 'pr', 'reopen', '3' }, vim.list_slice(reopen, 1, 4))
    assert.truthy(vim.tbl_contains(reopen, '-R'))
  end)

  it('returns correct pr_json_fields', function()
    local f = gh.pr_fields
    assert.equals('number', f.number)
    assert.equals('headRefName', f.branch)
    assert.equals('createdAt', f.created_at)
  end)

  it('normalizes completed run to conclusion', function()
    local run = gh:normalize_run({
      databaseId = 123,
      name = 'CI',
      headBranch = 'main',
      status = 'completed',
      conclusion = 'success',
      event = 'push',
      url = 'https://example.com',
      createdAt = '2025-01-01T00:00:00Z',
    })
    assert.equals('123', run.id)
    assert.equals('success', run.status)
    assert.equals('main', run.branch)
  end)

  it('preserves in_progress status in normalize_run', function()
    assert.equals(
      'in_progress',
      gh:normalize_run({ databaseId = 1, status = 'in_progress' }).status
    )
  end)
end)

describe('github browse', function()
  local captured
  local old_preload
  local old_system
  local old_ui_open
  local gh

  before_each(function()
    captured = {}
    old_system = vim.system
    old_ui_open = vim.ui.open
    old_preload = {
      ['forge.logger'] = package.preload['forge.logger'],
    }

    package.preload['forge.logger'] = function()
      return {
        error = function(msg)
          captured.error = msg
        end,
        warn = function() end,
        info = function() end,
        debug = function() end,
      }
    end

    vim.system = function(cmd, _, cb)
      captured.cmd = cmd
      if cb then
        cb({
          code = 0,
          stdout = 'https://example.com/repo/blob/main/lua/forge/init.lua#L10\n',
          stderr = '',
        })
      end
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    vim.ui.open = function(url)
      captured.url = url
      return {}, nil
    end

    package.loaded['forge.logger'] = nil
    package.loaded['forge.github'] = nil
    gh = require('forge.github')
  end)

  after_each(function()
    vim.system = old_system
    vim.ui.open = old_ui_open
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.loaded['forge.logger'] = nil
    package.loaded['forge.github'] = nil
  end)

  it('opens GitHub browse targets through vim.ui.open', function()
    gh:browse('lua/forge/init.lua:10', 'main')

    vim.wait(100, function()
      return captured.url ~= nil
    end)

    assert.same(
      { 'gh', 'browse', 'lua/forge/init.lua:10', '--branch', 'main' },
      vim.list_slice(captured.cmd, 1, 5)
    )
    assert.same('--no-browser', captured.cmd[#captured.cmd])
    assert.truthy(vim.tbl_contains(captured.cmd, '-R'))
    assert.equals('https://example.com/repo/blob/main/lua/forge/init.lua#L10', captured.url)
    assert.is_nil(captured.error)
  end)

  it('logs browse resolution failures from gh', function()
    vim.system = function(cmd, _, cb)
      captured.cmd = cmd
      if cb then
        cb({
          code = 1,
          stdout = '',
          stderr = 'exit status 1',
        })
      end
      return {
        wait = function()
          return { code = 1 }
        end,
      }
    end

    gh:browse_branch('main')

    vim.wait(100, function()
      return captured.error ~= nil
    end)

    assert.same({ 'gh', 'browse', '--branch', 'main' }, vim.list_slice(captured.cmd, 1, 4))
    assert.same('--no-browser', captured.cmd[#captured.cmd])
    assert.truthy(vim.tbl_contains(captured.cmd, '-R'))
    assert.equals('exit status 1', captured.error)
    assert.is_nil(captured.url)
  end)
end)

describe('gitlab', function()
  local gl = require('forge.gitlab')

  it('has correct metadata', function()
    assert.equals('glab', gl.cli)
    assert.equals('gitlab', gl.name)
    assert.equals('mr', gl.kinds.pr)
    assert.equals('PR', gl.labels.pr_one)
    assert.equals('PRs', gl.labels.pr)
    assert.equals('Pull Requests', gl.labels.pr_full)
  end)

  it('builds list_pr_json_cmd with state variants', function()
    local cmd = gl:list_pr_json_cmd('open')
    assert.equals('glab', cmd[1])
    assert.equals('mr', cmd[2])
    assert.truthy(vim.tbl_contains(gl:list_pr_json_cmd('closed'), '--closed'))
    assert.truthy(vim.tbl_contains(gl:list_pr_json_cmd('all'), '--all'))
  end)

  it('respects explicit issue list limits', function()
    local cmd = gl:list_issue_json_cmd('open', 44)
    assert.truthy(vim.tbl_contains(cmd, '--per-page'))
    assert.truthy(vim.tbl_contains(cmd, '44'))
  end)

  it('builds merge_cmd with method flags', function()
    local squash = gl:merge_cmd('5', 'squash')
    assert.same({ 'glab', 'mr', 'merge', '5' }, vim.list_slice(squash, 1, 4))
    assert.truthy(vim.tbl_contains(squash, '--squash'))
    assert.truthy(vim.tbl_contains(squash, '-R'))

    local rebase = gl:merge_cmd('5', 'rebase')
    assert.same({ 'glab', 'mr', 'merge', '5' }, vim.list_slice(rebase, 1, 4))
    assert.truthy(vim.tbl_contains(rebase, '--rebase'))
    assert.truthy(vim.tbl_contains(rebase, '-R'))

    local merge = gl:merge_cmd('5', 'merge')
    assert.same({ 'glab', 'mr', 'merge', '5' }, vim.list_slice(merge, 1, 4))
    assert.truthy(vim.tbl_contains(merge, '-R'))
  end)

  it('builds merge_cmd without method flags', function()
    local cmd = gl:merge_cmd('5')
    assert.same({ 'glab', 'mr', 'merge', '5' }, vim.list_slice(cmd, 1, 4))
    assert.truthy(vim.tbl_contains(cmd, '-R'))
    assert.falsy(vim.tbl_contains(cmd, '--squash'))
    assert.falsy(vim.tbl_contains(cmd, '--rebase'))
  end)

  it('builds create_pr_cmd with --description and --target-branch', function()
    local cmd = gl:create_pr_cmd('title', 'desc', 'develop', false, nil)
    assert.truthy(vim.tbl_contains(cmd, '--description'))
    assert.truthy(vim.tbl_contains(cmd, '--target-branch'))
    assert.truthy(vim.tbl_contains(cmd, '--yes'))
  end)

  it('returns correct pr_json_fields', function()
    local f = gl.pr_fields
    assert.equals('iid', f.number)
    assert.equals('source_branch', f.branch)
    assert.equals('created_at', f.created_at)
  end)

  it('extracts MR number from ref in normalize_run', function()
    local run = gl:normalize_run({
      id = 456,
      ref = 'refs/merge-requests/10/head',
      status = 'success',
      source = 'push',
      web_url = 'https://example.com',
      created_at = '2025-01-01T00:00:00Z',
    })
    assert.equals('456', run.id)
    assert.equals('!10', run.name)
  end)

  it('uses ref as name for non-MR refs', function()
    assert.equals('main', gl:normalize_run({ id = 1, ref = 'main', status = 'running' }).name)
  end)
end)

describe('codeberg', function()
  local cb = require('forge.codeberg')

  it('has correct metadata', function()
    assert.equals('tea', cb.cli)
    assert.equals('codeberg', cb.name)
    assert.equals('pulls', cb.kinds.pr)
    assert.equals('issues', cb.kinds.issue)
  end)

  it('builds list_pr_json_cmd with --fields', function()
    local cmd = cb:list_pr_json_cmd('open')
    assert.equals('tea', cmd[1])
    assert.truthy(vim.tbl_contains(cmd, '--fields'))
  end)

  it('respects explicit issue list limits', function()
    local cmd = cb:list_issue_json_cmd('open', 66)
    assert.truthy(vim.tbl_contains(cmd, '--limit'))
    assert.truthy(vim.tbl_contains(cmd, '66'))
  end)

  it('builds merge_cmd with --style', function()
    local cmd = cb:merge_cmd('7', 'squash')
    assert.same({ 'tea', 'pr', 'merge', '7', '--style', 'squash' }, vim.list_slice(cmd, 1, 6))
    assert.truthy(vim.tbl_contains(cmd, '--repo'))
  end)

  it('builds merge_cmd without --style', function()
    local cmd = cb:merge_cmd('7')
    assert.same({ 'tea', 'pr', 'merge', '7' }, vim.list_slice(cmd, 1, 4))
    assert.truthy(vim.tbl_contains(cmd, '--repo'))
    assert.falsy(vim.tbl_contains(cmd, '--style'))
  end)

  it('ignores draft and reviewers in create_pr_cmd', function()
    local cmd = cb:create_pr_cmd('title', 'body', 'main', true, { 'alice' })
    assert.falsy(vim.tbl_contains(cmd, '--draft'))
    assert.falsy(vim.tbl_contains(cmd, '--reviewer'))
    assert.truthy(vim.tbl_contains(cmd, '--base'))
  end)

  it('returns correct pr_json_fields', function()
    local f = cb.pr_fields
    assert.equals('index', f.number)
    assert.equals('head', f.branch)
    assert.equals('poster', f.author)
  end)

  it('returns nil from draft_toggle_cmd', function()
    assert.is_nil(cb:draft_toggle_cmd('1', true))
    assert.is_nil(cb:draft_toggle_cmd('1', false))
  end)

  it('uses tea api owner/repo placeholders for scoped fetches', function()
    local checks_cmd = cb:checks_json_cmd('7', { repo_arg = 'forgejo/tea-test' })
    assert.truthy(checks_cmd[3]:find('/repos/{owner}/{repo}/pulls/7', 1, true))
    assert.truthy(checks_cmd[3]:find('/repos/{owner}/{repo}/commits/$SHA/status', 1, true))

    local details_cmd = cb:fetch_pr_details_cmd('7', { repo_arg = 'forgejo/tea-test' })
    assert.truthy(details_cmd[3]:find('/repos/{owner}/{repo}/pulls/7', 1, true))

    local default_cmd = cb:default_branch_cmd({ repo_arg = 'forgejo/tea-test' })
    assert.truthy(default_cmd[3]:find('/repos/{owner}/{repo}', 1, true))
  end)

  it('uses tea releases commands for release list and delete', function()
    assert.same(
      { 'sh', '-c', 'tea releases list --limit 30 --output json --repo forgejo/tea-test' },
      cb:list_releases_json_cmd({ repo_arg = 'forgejo/tea-test' })
    )
    assert.same(
      { 'sh', '-c', 'tea releases delete --confirm --repo forgejo/tea-test v1.2.3' },
      cb:delete_release_cmd('v1.2.3', { repo_arg = 'forgejo/tea-test' })
    )
  end)
end)
