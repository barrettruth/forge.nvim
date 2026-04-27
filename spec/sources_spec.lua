vim.opt.runtimepath:prepend(vim.fn.getcwd())

package.preload['fzf-lua.utils'] = function()
  return {
    ansi_from_hl = function(_, text)
      return text
    end,
  }
end

describe('github', function()
  local gh = require('forge.backends.github')

  it('has correct metadata', function()
    assert.equals('gh', gh.cli)
    assert.equals('github', gh.name)
    assert.equals('pr', gh.kinds.pr)
    assert.equals('issue', gh.kinds.issue)
    assert.equals('GitHub', gh.labels.forge_name)
    assert.equals('CI/CD runs', gh.labels.ci_inline)
    assert.is_true(gh.capabilities.ci_terminal_view)
  end)

  it('parses PR head with scope from headRepository fields', function()
    local head = gh:parse_pr_head({
      headRefName = 'feature',
      headRepository = { name = 'fork', nameWithOwner = 'contributor/fork' },
      headRepositoryOwner = { login = 'contributor' },
    })
    assert.equals('feature', head.branch)
    assert.equals('contributor/fork', head.scope.slug)
    assert.equals('github.com', head.scope.host)
  end)

  it('respects base_scope host when constructing the head scope', function()
    local head = gh:parse_pr_head({
      headRefName = 'feature',
      headRepository = { name = 'fork', nameWithOwner = 'contributor/fork' },
      headRepositoryOwner = { login = 'contributor' },
    }, { kind = 'github', host = 'ghe.example.com' })
    assert.equals('ghe.example.com', head.scope.host)
  end)

  it('match_head compares branch and scope', function()
    local scope = gh:parse_pr_head({
      headRefName = 'feature',
      headRepository = { name = 'fork', nameWithOwner = 'contributor/fork' },
      headRepositoryOwner = { login = 'contributor' },
    }).scope
    assert.is_true(gh:match_head({ branch = 'feature', scope = scope }, {
      branch = 'feature',
      scope = scope,
    }))
    assert.is_false(gh:match_head({ branch = 'feature', scope = scope }, {
      branch = 'other',
      scope = scope,
    }))
  end)

  it('builds list_pr_json_cmd', function()
    local cmd = gh:list_pr_json_cmd('open')
    assert.equals('gh', cmd[1])
    assert.truthy(vim.tbl_contains(cmd, '--state'))
    assert.truthy(vim.tbl_contains(cmd, 'open'))
    assert.truthy(vim.tbl_contains(cmd, '--json'))
  end)

  it('builds pr_for_branch_cmd with explicit state filters', function()
    local cmd = gh:pr_for_branch_cmd('topic', { repo_arg = 'owner/repo' }, 'merged')
    assert.same({ 'gh', 'pr', 'list' }, vim.list_slice(cmd, 1, 3))
    assert.truthy(vim.tbl_contains(cmd, '--head'))
    assert.truthy(vim.tbl_contains(cmd, 'topic'))
    assert.truthy(vim.tbl_contains(cmd, '--state'))
    assert.truthy(vim.tbl_contains(cmd, 'merged'))
    assert.truthy(vim.tbl_contains(cmd, '-R'))
    assert.truthy(vim.tbl_contains(cmd, 'owner/repo'))
  end)

  it('respects explicit PR list limits', function()
    local cmd = gh:list_pr_json_cmd('open', 55)
    assert.truthy(vim.tbl_contains(cmd, '--limit'))
    assert.truthy(vim.tbl_contains(cmd, '55'))
  end)

  it('respects explicit release list limits', function()
    local cmd = gh:list_releases_json_cmd({ repo_arg = 'owner/repo' }, 42)
    assert.truthy(vim.tbl_contains(cmd, '--limit'))
    assert.truthy(vim.tbl_contains(cmd, '42'))
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

  it('forces tty color for run view summaries', function()
    local cmd = gh:view_cmd('24423079286', { scope = { repo_arg = 'owner/repo' } })
    assert.same(
      { 'env', 'GH_FORCE_TTY=1000', 'CLICOLOR_FORCE=1', 'gh', 'run', 'view' },
      vim.list_slice(cmd, 1, 6)
    )
    assert.truthy(vim.tbl_contains(cmd, '24423079286'))
    assert.truthy(vim.tbl_contains(cmd, '-R'))
    assert.truthy(vim.tbl_contains(cmd, 'owner/repo'))
  end)

  it('builds create_pr_cmd', function()
    local cmd = gh:create_pr_cmd('title', 'body', 'main', false, nil, {
      draft = true,
      labels = { 'bug' },
      assignees = { 'alice' },
      reviewers = { 'bob' },
      milestone = 'v1',
    })
    assert.truthy(vim.tbl_contains(cmd, '--title'))
    assert.truthy(vim.tbl_contains(cmd, '--base'))
    assert.truthy(vim.tbl_contains(cmd, '--draft'))
    assert.truthy(vim.tbl_contains(cmd, '--label'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'alice'))
    assert.truthy(vim.tbl_contains(cmd, '--reviewer'))
    assert.truthy(vim.tbl_contains(cmd, 'bob'))
    assert.truthy(vim.tbl_contains(cmd, '--milestone'))
    assert.truthy(vim.tbl_contains(cmd, 'v1'))
  end)

  it('builds issue detail and simplified issue commands', function()
    local pr_details = gh:fetch_pr_details_cmd('23', { repo_arg = 'owner/repo' })
    assert.same({ 'gh', 'pr', 'view', '23' }, vim.list_slice(pr_details, 1, 4))
    assert.truthy(
      vim.tbl_contains(
        pr_details,
        'title,body,isDraft,state,mergedAt,headRefName,headRepository,headRepositoryOwner,baseRefName,labels,assignees,reviewRequests,milestone,url'
      )
    )

    local details = gh:fetch_issue_details_cmd('23', { repo_arg = 'owner/repo' })
    assert.same({ 'gh', 'issue', 'view', '23' }, vim.list_slice(details, 1, 4))
    assert.truthy(vim.tbl_contains(details, '--json'))
    assert.truthy(vim.tbl_contains(details, 'title,body,labels,assignees,milestone,url'))

    local create = gh:create_issue_cmd('title', 'body', { 'bug' }, { repo_arg = 'owner/repo' }, {
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    })
    assert.truthy(vim.tbl_contains(create, '--label'))
    assert.truthy(vim.tbl_contains(create, 'bug'))
    assert.truthy(vim.tbl_contains(create, '--assignee'))
    assert.truthy(vim.tbl_contains(create, 'alice'))
    assert.truthy(vim.tbl_contains(create, '--milestone'))
    assert.truthy(vim.tbl_contains(create, 'v1'))

    local cmd = gh:update_issue_cmd('23', 'title', 'body', { repo_arg = 'owner/repo' }, {
      labels = { 'docs' },
      assignees = { 'bob' },
      milestone = '',
    }, {
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    })
    assert.truthy(vim.tbl_contains(cmd, '--add-label'))
    assert.truthy(vim.tbl_contains(cmd, 'docs'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-label'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--add-assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'bob'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'alice'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-milestone'))
  end)

  it('parses fetched PR and issue metadata', function()
    assert.same(
      {
        title = 'title',
        body = 'body',
        draft = true,
        head_branch = 'topic',
        base_branch = 'main',
        labels = { 'bug' },
        assignees = { 'alice' },
        reviewers = { 'bob' },
        milestone = 'v1',
      },
      gh:parse_pr_details({
        title = 'title',
        body = 'body',
        isDraft = true,
        headRefName = 'topic',
        baseRefName = 'main',
        labels = {
          { name = 'bug' },
        },
        assignees = {
          { login = 'alice' },
        },
        reviewRequests = {
          { login = 'bob' },
        },
        milestone = {
          title = 'v1',
        },
      })
    )

    assert.same(
      {
        title = 'title',
        body = 'body',
        labels = { 'bug' },
        assignees = { 'alice' },
        milestone = 'v1',
      },
      gh:parse_issue_details({
        title = 'title',
        body = 'body',
        labels = {
          { name = 'bug' },
        },
        assignees = {
          { login = 'alice' },
        },
        milestone = {
          title = 'v1',
        },
      })
    )
  end)

  it('adds draft flag to create_pr_cmd', function()
    assert.truthy(vim.tbl_contains(gh:create_pr_cmd('t', 'b', 'main', true), '--draft'))
  end)

  it('builds update_pr_cmd metadata deltas', function()
    local cmd = gh:update_pr_cmd('23', 'title', 'body', { repo_arg = 'owner/repo' }, {
      labels = { 'docs' },
      assignees = { 'bob' },
      reviewers = { 'carol' },
      milestone = '',
      draft = true,
    }, {
      labels = { 'bug' },
      assignees = { 'alice' },
      reviewers = { 'dave' },
      milestone = 'v1',
      draft = false,
    })

    assert.truthy(vim.tbl_contains(cmd, '--add-label'))
    assert.truthy(vim.tbl_contains(cmd, 'docs'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-label'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--add-assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'bob'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'alice'))
    assert.truthy(vim.tbl_contains(cmd, '--add-reviewer'))
    assert.truthy(vim.tbl_contains(cmd, 'carol'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-reviewer'))
    assert.truthy(vim.tbl_contains(cmd, 'dave'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-milestone'))
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

  it('prefers displayTitle for normalized run names', function()
    local run = gh:normalize_run({
      databaseId = 123,
      name = 'quality',
      displayTitle = 'fix(ci): add load more for repo runs (#196)',
      headBranch = 'main',
      status = 'completed',
      conclusion = 'success',
    })
    assert.equals('fix(ci): add load more for repo runs (#196)', run.name)
  end)

  it('builds list_web_url for each kind', function()
    local scope = { web_url = 'https://github.com/owner/repo' }
    assert.equals('https://github.com/owner/repo/pulls', gh:list_web_url('pr', scope))
    assert.equals('https://github.com/owner/repo/issues', gh:list_web_url('issue', scope))
    assert.equals('https://github.com/owner/repo/actions', gh:list_web_url('ci', scope))
    assert.equals('https://github.com/owner/repo/releases', gh:list_web_url('release', scope))
  end)

  it('returns nil from list_web_url when base url is empty', function()
    assert.is_nil(gh:list_web_url('pr', { web_url = '' }))
  end)

  it('returns nil from list_web_url for unknown kinds', function()
    local scope = { web_url = 'https://github.com/owner/repo' }
    assert.is_nil(gh:list_web_url('bogus', scope))
  end)

  it('builds a run web url and browse_run target', function()
    local scope = { web_url = 'https://github.com/owner/repo' }
    local old_open = vim.ui.open
    local opened
    vim.ui.open = function(url)
      opened = url
      return {}, nil
    end

    assert.equals('https://github.com/owner/repo/actions/runs/123', gh:run_web_url('123', scope))
    gh:browse_run('123', scope)

    vim.ui.open = old_open
    assert.equals('https://github.com/owner/repo/actions/runs/123', opened)
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
    package.loaded['forge.backends.github'] = nil
    gh = require('forge.backends.github')
  end)

  after_each(function()
    vim.system = old_system
    vim.ui.open = old_ui_open
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.loaded['forge.logger'] = nil
    package.loaded['forge.backends.github'] = nil
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

  it('dispatches browse_subject through `gh browse <num>`', function()
    vim.system = function(cmd, _, cb)
      captured.cmd = cmd
      if cb then
        cb({
          code = 0,
          stdout = 'https://github.com/owner/repo/issues/42\n',
          stderr = '',
        })
      end
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    gh:browse_subject('42', { repo_arg = 'owner/repo' })

    vim.wait(100, function()
      return captured.url ~= nil
    end)

    assert.same({ 'gh', 'browse', '42', '-R', 'owner/repo' }, vim.list_slice(captured.cmd, 1, 5))
    assert.same('--no-browser', captured.cmd[#captured.cmd])
    assert.equals('https://github.com/owner/repo/issues/42', captured.url)
    assert.is_nil(captured.error)
  end)

  it('logs browse_subject resolution failures from gh', function()
    vim.system = function(cmd, _, cb)
      captured.cmd = cmd
      if cb then
        cb({
          code = 1,
          stdout = '',
          stderr = 'no such issue or pr',
        })
      end
      return {
        wait = function()
          return { code = 1 }
        end,
      }
    end

    gh:browse_subject('999', { repo_arg = 'owner/repo' })

    vim.wait(100, function()
      return captured.error ~= nil
    end)

    assert.equals('no such issue or pr', captured.error)
    assert.is_nil(captured.url)
  end)
end)

describe('gitlab', function()
  local gl = require('forge.backends.gitlab')

  it('has correct metadata', function()
    assert.equals('glab', gl.cli)
    assert.equals('gitlab', gl.name)
    assert.equals('mr', gl.kinds.pr)
    assert.equals('MR', gl.labels.pr_one)
    assert.equals('Merge Requests', gl.labels.pr)
    assert.equals('Merge Requests', gl.labels.pr_full)
    assert.equals('Pipelines', gl.labels.ci)
    assert.equals('GitLab', gl.labels.forge_name)
    assert.equals('pipelines', gl.labels.ci_inline)
    assert.is_nil(gl.capabilities.ci_terminal_view)
  end)

  it('parses MR head with project_id from source fields', function()
    local head = gl:parse_pr_head({
      source_branch = 'topic',
      source_project_id = 12345,
    })
    assert.equals('topic', head.branch)
    assert.equals('12345', head.project_id)
    assert.is_nil(head.scope)
  end)

  it('match_head compares by project_id when both sides have one', function()
    assert.is_true(gl:match_head({ branch = 'topic', project_id = '42' }, {
      branch = 'topic',
      project_id = '42',
    }))
    assert.is_false(gl:match_head({ branch = 'topic', project_id = '42' }, {
      branch = 'topic',
      project_id = '99',
    }))
    assert.is_false(gl:match_head({ branch = 'topic', project_id = '42' }, {
      branch = 'other',
      project_id = '42',
    }))
  end)

  it('builds list_pr_json_cmd with state variants', function()
    local cmd = gl:list_pr_json_cmd('open')
    assert.equals('glab', cmd[1])
    assert.equals('mr', cmd[2])
    assert.truthy(vim.tbl_contains(gl:list_pr_json_cmd('closed'), '--closed'))
    assert.truthy(vim.tbl_contains(gl:list_pr_json_cmd('all'), '--all'))
  end)

  it('builds pr_for_branch_cmd with state variants', function()
    local closed = gl:pr_for_branch_cmd('topic', { repo_arg = 'group/repo' }, 'closed')
    local merged = gl:pr_for_branch_cmd('topic', { repo_arg = 'group/repo' }, 'merged')
    local all = gl:pr_for_branch_cmd('topic', { repo_arg = 'group/repo' }, 'all')
    assert.equals('sh', closed[1])
    assert.truthy(closed[3]:find("--source%-branch 'topic'", 1))
    assert.truthy(closed[3]:find('--closed', 1, true))
    assert.truthy(merged[3]:find('--merged', 1, true))
    assert.truthy(all[3]:find('--all', 1, true))
  end)

  it('respects explicit issue list limits', function()
    local cmd = gl:list_issue_json_cmd('open', 44)
    assert.truthy(vim.tbl_contains(cmd, '--per-page'))
    assert.truthy(vim.tbl_contains(cmd, '44'))
  end)

  it('respects explicit release list limits', function()
    local cmd = gl:list_releases_json_cmd({ repo_arg = 'group/repo' }, 42)
    assert.truthy(vim.tbl_contains(cmd, '--per-page'))
    assert.truthy(vim.tbl_contains(cmd, '42'))
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
    local cmd = gl:create_pr_cmd('title', 'desc', 'develop', false, nil, {
      draft = true,
      labels = { 'bug' },
      assignees = { 'alice' },
      reviewers = { 'bob' },
      milestone = 'v1',
    })
    assert.truthy(vim.tbl_contains(cmd, '--description'))
    assert.truthy(vim.tbl_contains(cmd, '--target-branch'))
    assert.truthy(vim.tbl_contains(cmd, '--yes'))
    assert.truthy(vim.tbl_contains(cmd, '--draft'))
    assert.truthy(vim.tbl_contains(cmd, '--label'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'alice'))
    assert.truthy(vim.tbl_contains(cmd, '--reviewer'))
    assert.truthy(vim.tbl_contains(cmd, 'bob'))
    assert.truthy(vim.tbl_contains(cmd, '--milestone'))
    assert.truthy(vim.tbl_contains(cmd, 'v1'))
  end)

  it('builds issue detail and simplified issue commands', function()
    local details = gl:fetch_issue_details_cmd('23', { repo_arg = 'group/repo' })
    assert.same(
      { 'glab', 'issue', 'view', '23', '--output', 'json' },
      vim.list_slice(details, 1, 6)
    )

    local create = gl:create_issue_cmd('title', 'body', { 'bug' }, { repo_arg = 'group/repo' }, {
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    })
    assert.truthy(vim.tbl_contains(create, '--label'))
    assert.truthy(vim.tbl_contains(create, 'bug'))
    assert.truthy(vim.tbl_contains(create, '--assignee'))
    assert.truthy(vim.tbl_contains(create, 'alice'))
    assert.truthy(vim.tbl_contains(create, '--milestone'))
    assert.truthy(vim.tbl_contains(create, 'v1'))

    local cmd = gl:update_issue_cmd('23', 'title', 'body', { repo_arg = 'group/repo' }, {
      labels = { 'docs' },
      assignees = { 'bob' },
      milestone = '',
    }, {
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    })
    assert.truthy(vim.tbl_contains(cmd, '--label'))
    assert.truthy(vim.tbl_contains(cmd, 'docs'))
    assert.truthy(vim.tbl_contains(cmd, '--unlabel'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'bob'))
    assert.truthy(vim.tbl_contains(cmd, '--milestone'))
    assert.truthy(vim.tbl_contains(cmd, '0'))
  end)

  it('builds update_pr_cmd reviewer and label changes', function()
    local cmd = gl:update_pr_cmd('23', 'title', 'body', { repo_arg = 'group/repo' }, {
      labels = { 'docs' },
      assignees = { 'bob' },
      reviewers = {},
      milestone = '',
      draft = true,
    }, {
      labels = { 'bug' },
      assignees = { 'alice' },
      reviewers = { 'carol' },
      milestone = 'v1',
      draft = false,
    })

    assert.truthy(vim.tbl_contains(cmd, '--label'))
    assert.truthy(vim.tbl_contains(cmd, 'docs'))
    assert.truthy(vim.tbl_contains(cmd, '--unlabel'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'bob'))
    assert.truthy(vim.tbl_contains(cmd, '--reviewer'))
    assert.truthy(vim.tbl_contains(cmd, '-carol'))
    assert.truthy(vim.tbl_contains(cmd, '--milestone'))
    assert.truthy(vim.tbl_contains(cmd, '0'))
  end)

  it('parses fetched MR and issue metadata', function()
    assert.same(
      {
        title = 'title',
        body = 'body',
        draft = true,
        head_branch = 'topic',
        base_branch = 'main',
        labels = { 'bug' },
        assignees = { 'alice' },
        reviewers = { 'bob' },
        milestone = 'v1',
      },
      gl:parse_pr_details({
        title = 'title',
        description = 'body',
        draft = true,
        source_branch = 'topic',
        target_branch = 'main',
        labels = { 'bug' },
        assignees = {
          { username = 'alice' },
        },
        reviewers = {
          { username = 'bob' },
        },
        milestone = {
          title = 'v1',
        },
      })
    )

    assert.same(
      {
        title = 'title',
        body = 'body',
        labels = { 'bug' },
        assignees = { 'alice' },
        milestone = 'v1',
      },
      gl:parse_issue_details({
        title = 'title',
        description = 'body',
        labels = { 'bug' },
        assignees = {
          { username = 'alice' },
        },
        milestone = {
          title = 'v1',
        },
      })
    )
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

  it('builds list_web_url for each kind', function()
    local scope = { web_url = 'https://gitlab.com/group/repo' }
    assert.equals('https://gitlab.com/group/repo/-/merge_requests', gl:list_web_url('pr', scope))
    assert.equals('https://gitlab.com/group/repo/-/issues', gl:list_web_url('issue', scope))
    assert.equals('https://gitlab.com/group/repo/-/pipelines', gl:list_web_url('ci', scope))
    assert.equals('https://gitlab.com/group/repo/-/releases', gl:list_web_url('release', scope))
  end)

  it('returns nil from list_web_url when base url is empty', function()
    assert.is_nil(gl:list_web_url('pr', { web_url = '' }))
  end)

  it('returns nil from list_web_url for unknown kinds', function()
    local scope = { web_url = 'https://gitlab.com/group/repo' }
    assert.is_nil(gl:list_web_url('bogus', scope))
  end)

  it('builds a run web url and browse_run target', function()
    local scope = { web_url = 'https://gitlab.com/group/repo' }
    local old_open = vim.ui.open
    local opened
    vim.ui.open = function(url)
      opened = url
      return {}, nil
    end

    assert.equals('https://gitlab.com/group/repo/-/pipelines/123', gl:run_web_url('123', scope))
    gl:browse_run('123', scope)

    vim.ui.open = old_open
    assert.equals('https://gitlab.com/group/repo/-/pipelines/123', opened)
  end)
end)

describe('gitlab browse_subject', function()
  local captured
  local old_preload
  local old_system
  local old_ui_open
  local gl

  local function gitlab_scope()
    return { kind = 'gitlab', host = 'gitlab.com', slug = 'group/repo' }
  end

  local function mock_glab_api(scenarios)
    return function(cmd, _, cb)
      table.insert(captured.cmds, cmd)
      local path = cmd[5] or ''
      local result
      if path:find('/merge_requests/', 1, true) then
        result = scenarios.mr or { code = 1, stdout = '', stderr = 'not found' }
      elseif path:find('/issues/', 1, true) then
        result = scenarios.issue or { code = 1, stdout = '', stderr = 'not found' }
      else
        result = { code = 1, stdout = '', stderr = 'unexpected path' }
      end
      if cb then
        cb(result)
      end
      return {
        wait = function()
          return result
        end,
      }
    end
  end

  before_each(function()
    captured = { cmds = {} }
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
        warn = function(msg)
          captured.warn = msg
        end,
        info = function() end,
        debug = function() end,
      }
    end

    vim.ui.open = function(url)
      captured.url = url
      return {}, nil
    end

    package.loaded['forge.logger'] = nil
    package.loaded['forge.backends.gitlab'] = nil
    gl = require('forge.backends.gitlab')
  end)

  after_each(function()
    vim.system = old_system
    vim.ui.open = old_ui_open
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.loaded['forge.logger'] = nil
    package.loaded['forge.backends.gitlab'] = nil
  end)

  it('opens the MR when only the MR exists', function()
    vim.system = mock_glab_api({
      mr = {
        code = 0,
        stdout = '{"web_url":"https://gitlab.com/group/repo/-/merge_requests/42"}',
      },
    })

    gl:browse_subject('42', gitlab_scope())

    vim.wait(100, function()
      return captured.url ~= nil
    end)

    assert.equals('https://gitlab.com/group/repo/-/merge_requests/42', captured.url)
    assert.is_nil(captured.warn)
    assert.is_nil(captured.error)
    assert.equals(2, #captured.cmds)
  end)

  it('opens the issue when only the issue exists', function()
    vim.system = mock_glab_api({
      issue = {
        code = 0,
        stdout = '{"web_url":"https://gitlab.com/group/repo/-/issues/42"}',
      },
    })

    gl:browse_subject('42', gitlab_scope())

    vim.wait(100, function()
      return captured.url ~= nil
    end)

    assert.equals('https://gitlab.com/group/repo/-/issues/42', captured.url)
    assert.is_nil(captured.warn)
    assert.is_nil(captured.error)
  end)

  it('warns ambiguous when both an MR and an issue exist', function()
    vim.system = mock_glab_api({
      mr = {
        code = 0,
        stdout = '{"web_url":"https://gitlab.com/group/repo/-/merge_requests/5"}',
      },
      issue = {
        code = 0,
        stdout = '{"web_url":"https://gitlab.com/group/repo/-/issues/5"}',
      },
    })

    gl:browse_subject('5', gitlab_scope())

    vim.wait(100, function()
      return captured.warn ~= nil
    end)

    assert.is_nil(captured.url)
    assert.matches('ambiguous', captured.warn)
    assert.matches('MR', captured.warn)
    assert.matches(':Forge pr browse 5', captured.warn)
    assert.matches(':Forge issue browse 5', captured.warn)
  end)

  it('warns not found when neither an MR nor an issue exists', function()
    vim.system = mock_glab_api({
      mr = { code = 1, stdout = '', stderr = 'not found' },
      issue = { code = 1, stdout = '', stderr = 'not found' },
    })

    gl:browse_subject('999', gitlab_scope())

    vim.wait(100, function()
      return captured.warn ~= nil
    end)

    assert.is_nil(captured.url)
    assert.matches('no MR or issue found for #999', captured.warn)
  end)

  it('uses --hostname from scope and encodes the project slug', function()
    vim.system = mock_glab_api({
      issue = {
        code = 0,
        stdout = '{"web_url":"https://gitlab.example.com/group/sub/repo/-/issues/7"}',
      },
    })

    gl:browse_subject(
      '7',
      { kind = 'gitlab', host = 'gitlab.example.com', slug = 'group/sub/repo' }
    )

    vim.wait(100, function()
      return captured.url ~= nil
    end)

    assert.is_true(#captured.cmds == 2)
    for _, cmd in ipairs(captured.cmds) do
      assert.equals('glab', cmd[1])
      assert.equals('api', cmd[2])
      assert.equals('--hostname', cmd[3])
      assert.equals('gitlab.example.com', cmd[4])
      assert.matches('group%%2Fsub%%2Frepo/', cmd[5])
    end
  end)
end)

describe('codeberg', function()
  local cb = require('forge.backends.codeberg')

  it('has correct metadata', function()
    assert.equals('tea', cb.cli)
    assert.equals('codeberg', cb.name)
    assert.equals('pulls', cb.kinds.pr)
    assert.equals('issues', cb.kinds.issue)
    assert.equals('Codeberg', cb.labels.forge_name)
    assert.equals('CI/CD runs', cb.labels.ci_inline)
    assert.is_nil(cb.capabilities.ci_terminal_view)
  end)

  it('parses PR head with scope from head.repo.full_name', function()
    local head = cb:parse_pr_head({
      head = {
        ref = 'feature',
        repo = { full_name = 'contributor/fork' },
      },
    })
    assert.equals('feature', head.branch)
    assert.equals('contributor/fork', head.scope.slug)
    assert.equals('codeberg.org', head.scope.host)
  end)

  it('respects base_scope host when constructing the head scope', function()
    local head = cb:parse_pr_head({
      head = {
        ref = 'feature',
        repo = { full_name = 'contributor/fork' },
      },
    }, { kind = 'codeberg', host = 'gitea.example.com' })
    assert.equals('gitea.example.com', head.scope.host)
  end)

  it('match_head compares branch and scope', function()
    local scope = cb:parse_pr_head({
      head = {
        ref = 'feature',
        repo = { full_name = 'contributor/fork' },
      },
    }).scope
    assert.is_true(cb:match_head({ branch = 'feature', scope = scope }, {
      branch = 'feature',
      scope = scope,
    }))
    assert.is_false(cb:match_head({ branch = 'feature', scope = scope }, {
      branch = 'other',
      scope = scope,
    }))
  end)

  it('builds list_pr_json_cmd with --fields', function()
    local cmd = cb:list_pr_json_cmd('open')
    assert.equals('tea', cmd[1])
    assert.truthy(vim.tbl_contains(cmd, '--fields'))
  end)

  it('builds pr_for_branch_cmd with explicit states', function()
    local cmd = cb:pr_for_branch_cmd('topic', { repo_arg = 'owner/repo' }, 'closed')
    assert.equals('sh', cmd[1])
    assert.truthy(cmd[3]:find('--state closed', 1, true))
    assert.truthy(cmd[3]:find('.head=="topic"', 1, true))
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

  it('ignores draft in create_pr_cmd', function()
    local cmd = cb:create_pr_cmd('title', 'body', 'main', true, nil, {
      draft = true,
      labels = { 'bug' },
      assignees = { 'alice' },
      reviewers = { 'bob' },
      milestone = 'v1',
    })
    assert.falsy(vim.tbl_contains(cmd, '--draft'))
    assert.truthy(vim.tbl_contains(cmd, '--base'))
    assert.truthy(vim.tbl_contains(cmd, '--labels'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--assignees'))
    assert.truthy(vim.tbl_contains(cmd, 'alice'))
    assert.falsy(vim.tbl_contains(cmd, '--add-reviewers'))
    assert.truthy(vim.tbl_contains(cmd, '--milestone'))
    assert.truthy(vim.tbl_contains(cmd, 'v1'))
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

    local issue_details_cmd = cb:fetch_issue_details_cmd('7', { repo_arg = 'forgejo/tea-test' })
    assert.truthy(issue_details_cmd[3]:find('/repos/{owner}/{repo}/issues/7', 1, true))

    local default_cmd = cb:default_branch_cmd({ repo_arg = 'forgejo/tea-test' })
    assert.truthy(default_cmd[3]:find('/repos/{owner}/{repo}', 1, true))
  end)

  it('builds simplified issue commands for tea', function()
    local create = cb:create_issue_cmd(
      'title',
      'body',
      { 'bug' },
      { repo_arg = 'forgejo/tea-test' },
      {
        labels = { 'bug' },
        assignees = { 'alice' },
        milestone = 'v1',
      }
    )
    assert.same({ 'tea', 'issues', 'create', '--title', 'title' }, vim.list_slice(create, 1, 5))
    assert.truthy(vim.tbl_contains(create, '--labels'))
    assert.truthy(vim.tbl_contains(create, 'bug'))
    assert.truthy(vim.tbl_contains(create, '--assignees'))
    assert.truthy(vim.tbl_contains(create, 'alice'))
    assert.truthy(vim.tbl_contains(create, '--milestone'))
    assert.truthy(vim.tbl_contains(create, 'v1'))

    local cmd = cb:update_issue_cmd('23', 'title', 'body', { repo_arg = 'forgejo/tea-test' }, {
      labels = { 'docs' },
      assignees = { 'bob' },
      milestone = '',
    }, {
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    })
    assert.same({ 'tea', 'issues', 'edit', '23' }, vim.list_slice(cmd, 1, 4))
    assert.truthy(vim.tbl_contains(cmd, '--add-labels'))
    assert.truthy(vim.tbl_contains(cmd, 'docs'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-labels'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--milestone'))
    assert.truthy(vim.tbl_contains(cmd, ''))
  end)

  it('parses fetched PR and issue metadata for tea', function()
    assert.same(
      {
        title = 'title',
        body = 'body',
        draft = true,
        head_branch = 'topic',
        base_branch = 'main',
        labels = { 'bug' },
        assignees = { 'alice' },
        reviewers = { 'bob' },
        milestone = 'v1',
      },
      cb:parse_pr_details({
        title = 'title',
        body = 'body',
        draft = true,
        head = { ref = 'topic' },
        base = { ref = 'main' },
        labels = {
          { name = 'bug' },
        },
        assignees = {
          { login = 'alice' },
        },
        requested_reviewers = {
          { login = 'bob' },
        },
        milestone = {
          title = 'v1',
        },
      })
    )

    assert.same(
      {
        title = 'title',
        body = 'body',
        labels = { 'bug' },
        assignees = { 'alice' },
        milestone = 'v1',
      },
      cb:parse_issue_details({
        title = 'title',
        body = 'body',
        labels = {
          { name = 'bug' },
        },
        assignees = {
          { login = 'alice' },
        },
        milestone = {
          title = 'v1',
        },
      })
    )
  end)

  it('uses tea releases commands for release list and delete', function()
    assert.same(
      { 'sh', '-c', 'tea releases list --limit 30 --output json --repo forgejo/tea-test' },
      cb:list_releases_json_cmd({ repo_arg = 'forgejo/tea-test' })
    )
    assert.same(
      { 'sh', '-c', 'tea releases list --limit 55 --output json --repo forgejo/tea-test' },
      cb:list_releases_json_cmd({ repo_arg = 'forgejo/tea-test' }, 55)
    )
    assert.same(
      { 'sh', '-c', 'tea releases delete --confirm --repo forgejo/tea-test v1.2.3' },
      cb:delete_release_cmd('v1.2.3', { repo_arg = 'forgejo/tea-test' })
    )
  end)

  it('builds list_web_url for each kind', function()
    local scope = { web_url = 'https://codeberg.org/owner/repo' }
    assert.equals('https://codeberg.org/owner/repo/pulls', cb:list_web_url('pr', scope))
    assert.equals('https://codeberg.org/owner/repo/issues', cb:list_web_url('issue', scope))
    assert.equals('https://codeberg.org/owner/repo/actions', cb:list_web_url('ci', scope))
    assert.equals('https://codeberg.org/owner/repo/releases', cb:list_web_url('release', scope))
  end)

  it('returns nil from list_web_url when base url is empty', function()
    assert.is_nil(cb:list_web_url('pr', { web_url = '' }))
  end)

  it('returns nil from list_web_url for unknown kinds', function()
    local scope = { web_url = 'https://codeberg.org/owner/repo' }
    assert.is_nil(cb:list_web_url('bogus', scope))
  end)

  it('builds a run web url and browse_run target', function()
    local scope = { web_url = 'https://codeberg.org/owner/repo' }
    local old_open = vim.ui.open
    local opened
    vim.ui.open = function(url)
      opened = url
      return {}, nil
    end

    assert.equals('https://codeberg.org/owner/repo/actions/runs/123', cb:run_web_url('123', scope))
    cb:browse_run('123', scope)

    vim.ui.open = old_open
    assert.equals('https://codeberg.org/owner/repo/actions/runs/123', opened)
  end)
end)

describe('codeberg browse_subject', function()
  local captured
  local old_preload
  local old_system
  local old_ui_open
  local cb

  local function codeberg_scope()
    return { repo_arg = 'forgejo/forgejo' }
  end

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
        warn = function(msg)
          captured.warn = msg
        end,
        info = function() end,
        debug = function() end,
      }
    end

    vim.ui.open = function(url)
      captured.url = url
      return {}, nil
    end

    package.loaded['forge.logger'] = nil
    package.loaded['forge.backends.codeberg'] = nil
    cb = require('forge.backends.codeberg')
  end)

  after_each(function()
    vim.system = old_system
    vim.ui.open = old_ui_open
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.loaded['forge.logger'] = nil
    package.loaded['forge.backends.codeberg'] = nil
  end)

  it('opens the html_url returned by tea api for an issue', function()
    vim.system = function(cmd, _, cb_fn)
      captured.cmd = cmd
      cb_fn({
        code = 0,
        stdout = '{"html_url":"https://codeberg.org/forgejo/forgejo/issues/42","pull_request":null}',
        stderr = '',
      })
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    cb:browse_subject('42', codeberg_scope())

    vim.wait(100, function()
      return captured.url ~= nil
    end)

    assert.same(
      { 'tea', 'api', '--repo', 'forgejo/forgejo', '/repos/{owner}/{repo}/issues/42' },
      captured.cmd
    )
    assert.equals('https://codeberg.org/forgejo/forgejo/issues/42', captured.url)
    assert.is_nil(captured.error)
  end)

  it('opens the html_url returned by tea api for a PR', function()
    vim.system = function(_, _, cb_fn)
      cb_fn({
        code = 0,
        stdout = '{"html_url":"https://codeberg.org/forgejo/forgejo/pulls/12272","pull_request":{"merged":true}}',
        stderr = '',
      })
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    cb:browse_subject('12272', codeberg_scope())

    vim.wait(100, function()
      return captured.url ~= nil
    end)

    assert.equals('https://codeberg.org/forgejo/forgejo/pulls/12272', captured.url)
    assert.is_nil(captured.error)
  end)

  it('warns not-found when tea api returns a 404', function()
    vim.system = function(_, _, cb_fn)
      cb_fn({
        code = 1,
        stdout = '',
        stderr = '404 not found',
      })
      return {
        wait = function()
          return { code = 1 }
        end,
      }
    end

    cb:browse_subject('999', codeberg_scope())

    vim.wait(100, function()
      return captured.warn ~= nil
    end)

    assert.is_nil(captured.url)
    assert.is_nil(captured.error)
    assert.equals('no PR or issue found for #999', captured.warn)
  end)

  it('surfaces tea api stderr on non-404 failures', function()
    vim.system = function(_, _, cb_fn)
      cb_fn({
        code = 1,
        stdout = '',
        stderr = 'Error: Authentication required',
      })
      return {
        wait = function()
          return { code = 1 }
        end,
      }
    end

    cb:browse_subject('42', codeberg_scope())

    vim.wait(100, function()
      return captured.error ~= nil
    end)

    assert.is_nil(captured.url)
    assert.is_nil(captured.warn)
    assert.equals('Error: Authentication required', captured.error)
  end)

  it('logs parse failure when tea api stdout is not JSON', function()
    vim.system = function(_, _, cb_fn)
      cb_fn({
        code = 0,
        stdout = 'not json at all',
        stderr = '',
      })
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end

    cb:browse_subject('42', codeberg_scope())

    vim.wait(100, function()
      return captured.error ~= nil
    end)

    assert.is_nil(captured.url)
    assert.equals('failed to parse #42 details', captured.error)
  end)
end)
