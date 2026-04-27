vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('submission integration', function()
  local captured
  local old_fn_system
  local old_system
  local old_feedkeys
  local old_schedule
  local old_preload

  before_each(function()
    captured = {
      calls = {},
      infos = {},
      warns = {},
      errors = {},
      cleared = 0,
    }

    old_fn_system = vim.fn.system
    old_system = vim.system
    old_feedkeys = vim.api.nvim_feedkeys
    old_schedule = vim.schedule
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.resolve'] = package.preload['forge.resolve'],
      ['forge.template'] = package.preload['forge.template'],
    }

    vim.fn.system = function(cmd)
      if cmd:match('^git diff %-%-stat ') then
        return ''
      end
      return ''
    end

    vim.api.nvim_feedkeys = function() end
    vim.schedule = function(fn)
      fn()
    end

    vim.system = function(cmd, _, cb)
      table.insert(captured.calls, cmd)
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      if cb then
        cb(result)
      end
      return {
        wait = function()
          return result
        end,
      }
    end

    package.preload['forge'] = function()
      return {
        clear_list = function()
          captured.cleared = captured.cleared + 1
        end,
        scope_repo_arg = function(scope)
          return scope and scope.repo_arg or ''
        end,
        remote_web_url = function()
          return ''
        end,
        scope_key = function(scope)
          return scope and scope.repo_arg or ''
        end,
        current_scope = function()
          return {
            kind = 'github',
            host = 'github.com',
            slug = 'owner/repo',
          }
        end,
      }
    end

    package.preload['forge.logger'] = function()
      return {
        debug = function() end,
        info = function(msg)
          table.insert(captured.infos, msg)
        end,
        warn = function(msg)
          table.insert(captured.warns, msg)
        end,
        error = function(msg)
          table.insert(captured.errors, msg)
        end,
      }
    end

    package.preload['forge.resolve'] = function()
      return {
        current_pr = function(opts)
          captured.current_pr_opts = opts
          return { num = '24' }
        end,
      }
    end

    package.preload['forge.template'] = function()
      return {
        normalize_body = function(s)
          return vim.trim(s):gsub('%s+', ' ')
        end,
        fill_from_commits = function()
          return 'title', 'body'
        end,
      }
    end

    package.loaded['forge'] = nil
    package.loaded['forge.backends.codeberg'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.backends.github'] = nil
    package.loaded['forge.backends.gitlab'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.resolve'] = nil
    package.loaded['forge.submission'] = nil
    package.loaded['forge.template'] = nil
  end)

  after_each(function()
    vim.fn.system = old_fn_system
    vim.system = old_system
    vim.api.nvim_feedkeys = old_feedkeys
    vim.schedule = old_schedule

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.resolve'] = old_preload['forge.resolve']
    package.preload['forge.template'] = old_preload['forge.template']

    package.loaded['forge'] = nil
    package.loaded['forge.backends.codeberg'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.backends.github'] = nil
    package.loaded['forge.backends.gitlab'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.resolve'] = nil
    package.loaded['forge.submission'] = nil
    package.loaded['forge.template'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match('^forge://') then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
    vim.cmd('enew!')
  end)

  it('submits GitHub issue metadata through compose into the real adapter', function()
    local compose = require('forge.compose')
    local gh = require('forge.backends.github')

    compose.open_issue(gh, {
      title = 'bug: ',
      body = '',
      labels = { 'bug' },
      assignees = { 'alice' },
    }, { repo_arg = 'owner/repo' })

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# fixed issue',
      '',
      'body',
      '',
      '<!--',
      '  Labels: bug, docs',
      '  Assignees: alice',
      '  Milestone: v1',
      '-->',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return #captured.calls > 0
    end)

    local cmd = captured.calls[1]
    assert.same({ 'gh', 'issue', 'create' }, vim.list_slice(cmd, 1, 3))
    assert.truthy(vim.tbl_contains(cmd, '--label'))
    assert.truthy(vim.tbl_contains(cmd, 'bug,docs'))
    assert.truthy(vim.tbl_contains(cmd, '--assignee'))
    assert.truthy(vim.tbl_contains(cmd, 'alice'))
    assert.truthy(vim.tbl_contains(cmd, '--milestone'))
    assert.truthy(vim.tbl_contains(cmd, 'v1'))
  end)

  it('submits GitLab PR updates and draft toggle through compose into the real adapter', function()
    local compose = require('forge.compose')
    local gl = require('forge.backends.gitlab')

    compose.open_pr_edit(gl, '23', {
      title = 'PR title',
      body = 'PR body',
      draft = false,
      head_branch = 'topic',
      base_branch = 'main',
      reviewers = { 'carol' },
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    }, 'topic', { repo_arg = 'group/repo' })

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# updated pr',
      '',
      'updated body',
      '',
      '<!--',
      '  Draft: true',
      '  Reviewers: bob',
      '  Labels: docs',
      '  Assignees: bob',
      '  Milestone: ',
      '-->',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return #captured.calls >= 2
    end)

    local update_cmd = captured.calls[1]
    local draft_cmd = captured.calls[2]
    assert.same({ 'glab', 'mr', 'update', '23' }, vim.list_slice(update_cmd, 1, 4))
    assert.truthy(vim.tbl_contains(update_cmd, '--label'))
    assert.truthy(vim.tbl_contains(update_cmd, 'docs'))
    assert.truthy(vim.tbl_contains(update_cmd, '--unlabel'))
    assert.truthy(vim.tbl_contains(update_cmd, 'bug'))
    assert.truthy(vim.tbl_contains(update_cmd, '--assignee'))
    assert.truthy(vim.tbl_contains(update_cmd, 'bob'))
    assert.truthy(vim.tbl_contains(update_cmd, '--reviewer'))
    assert.truthy(vim.tbl_contains(update_cmd, 'bob'))
    assert.truthy(vim.tbl_contains(update_cmd, '--milestone'))
    assert.truthy(vim.tbl_contains(update_cmd, '0'))
    assert.same({ 'glab', 'mr', 'update', '23', '--draft', '-R', 'group/repo' }, draft_cmd)
  end)

  it('submits Codeberg PR updates through compose using only supported metadata fields', function()
    local compose = require('forge.compose')
    local cb = require('forge.backends.codeberg')

    compose.open_pr_edit(cb, '23', {
      title = 'PR title',
      body = 'PR body',
      draft = true,
      head_branch = 'topic',
      base_branch = 'main',
      reviewers = { 'carol' },
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    }, 'topic', { repo_arg = 'forgejo/tea-test' })

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.is_false(vim.tbl_contains(lines, '  Draft: true'))
    assert.is_false(vim.tbl_contains(lines, '  Assignees: alice'))
    assert.is_true(vim.tbl_contains(lines, '  Reviewers: carol'))

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# updated pr',
      '',
      'updated body',
      '',
      '<!--',
      '  Reviewers: dave',
      '  Labels: docs',
      '  Assignees: bob',
      '  Milestone: ',
      '-->',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return #captured.calls > 0
    end)

    local cmd = captured.calls[1]
    assert.same({ 'tea', 'pr', 'edit', '23' }, vim.list_slice(cmd, 1, 4))
    assert.truthy(vim.tbl_contains(cmd, '--add-labels'))
    assert.truthy(vim.tbl_contains(cmd, 'docs'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-labels'))
    assert.truthy(vim.tbl_contains(cmd, 'bug'))
    assert.truthy(vim.tbl_contains(cmd, '--add-reviewers'))
    assert.truthy(vim.tbl_contains(cmd, 'dave'))
    assert.truthy(vim.tbl_contains(cmd, '--remove-reviewers'))
    assert.truthy(vim.tbl_contains(cmd, 'carol'))
    assert.truthy(vim.tbl_contains(cmd, '--milestone'))
    assert.falsy(vim.tbl_contains(cmd, '--add-assignees'))
  end)

  it('applies Codeberg PR reviewers after create when tea create cannot set them', function()
    local compose = require('forge.compose')
    local cb = require('forge.backends.codeberg')
    local ref = {
      kind = 'codeberg',
      host = 'codeberg.org',
      slug = 'forgejo/tea-test',
      repo_arg = 'forgejo/tea-test',
      web_url = 'https://codeberg.org/forgejo/tea-test',
    }

    vim.system = function(cmd, _, cb_fn)
      table.insert(captured.calls, cmd)
      local key = table.concat(cmd, ' ')
      local result = {
        code = 0,
        stdout = '',
        stderr = '',
      }
      if
        key
        == 'tea pr create --title created pr --description created body --base main --repo forgejo/tea-test --labels docs --assignees alice --milestone v1'
      then
        result.stdout = 'https://codeberg.org/forgejo/tea-test/pulls/24'
      end
      if cb_fn then
        cb_fn(result)
      end
      return {
        wait = function()
          return result
        end,
      }
    end

    compose.open_pr(
      cb,
      'topic',
      'main',
      false,
      { body = 'body' },
      ref,
      'origin',
      'origin/main',
      'HEAD',
      ref
    )

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# created pr',
      '',
      'created body',
      '',
      '<!--',
      '  Reviewers: carol',
      '  Labels: docs',
      '  Assignees: alice',
      '  Milestone: v1',
      '-->',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return #captured.calls >= 3
    end)

    assert.same({ 'git', 'push', '-u', 'origin', 'topic' }, captured.calls[1])
    assert.same({
      'tea',
      'pr',
      'create',
      '--title',
      'created pr',
      '--description',
      'created body',
      '--base',
      'main',
      '--repo',
      'forgejo/tea-test',
      '--labels',
      'docs',
      '--assignees',
      'alice',
      '--milestone',
      'v1',
    }, captured.calls[2])
    assert.same({
      forge = cb,
      scope = ref,
      head_branch = 'topic',
      head_scope = ref,
    }, captured.current_pr_opts)
    assert.same({ 'tea', 'pr', 'edit', '24' }, vim.list_slice(captured.calls[3], 1, 4))
    assert.truthy(vim.tbl_contains(captured.calls[3], '--add-reviewers'))
    assert.truthy(vim.tbl_contains(captured.calls[3], 'carol'))
    assert.falsy(vim.tbl_contains(captured.calls[3], '--add-labels'))
    assert.falsy(vim.tbl_contains(captured.calls[3], '--add-assignees'))
    assert.is_true(
      vim.tbl_contains(
        captured.infos,
        'created PR -> https://codeberg.org/forgejo/tea-test/pulls/24'
      )
    )
    assert.same({}, captured.errors)
  end)
end)
