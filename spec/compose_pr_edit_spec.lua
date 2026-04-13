vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('compose pr edit', function()
  local captured
  local old_fn_system
  local old_system
  local old_feedkeys
  local old_preload

  before_each(function()
    captured = {
      infos = {},
      warns = {},
      errors = {},
      cleared = 0,
      diff_stat = '',
    }

    old_fn_system = vim.fn.system
    old_system = vim.system
    old_feedkeys = vim.api.nvim_feedkeys
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
    }

    vim.api.nvim_feedkeys = function() end
    vim.fn.system = function(cmd)
      if cmd == 'git diff --stat origin/main..HEAD' then
        return captured.diff_stat
      end
      return ''
    end
    vim.system = function(cmd, _, cb)
      captured.cmd = cmd
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

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil
  end)

  after_each(function()
    vim.fn.system = old_fn_system
    vim.system = old_system
    vim.api.nvim_feedkeys = old_feedkeys

    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']

    package.loaded['forge'] = nil
    package.loaded['forge.compose'] = nil
    package.loaded['forge.logger'] = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.api.nvim_buf_get_name(buf) == 'forge://pr/23/edit'
      then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.cmd('enew!')
  end)

  it('shows fetched metadata in the comment header', function()
    local compose = require('forge.compose')
    compose.open_pr_edit(
      {
        labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
        capabilities = { draft = true, reviewers = true },
        name = 'github',
      },
      '23',
      {
        title = 'PR title',
        body = 'PR body',
        draft = false,
        head_branch = 'real-pr-head',
        base_branch = 'main',
        reviewers = { 'bob' },
        labels = { 'bug' },
        assignees = { 'alice' },
        milestone = 'v1',
      },
      'other-local-branch'
    )

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.is_truthy(vim.tbl_contains(lines, '  On branch real-pr-head against main.'))
    assert.is_false(vim.tbl_contains(lines, '  On branch other-local-branch against main.'))
    assert.is_true(vim.tbl_contains(lines, '  Draft: false'))
    assert.is_true(vim.tbl_contains(lines, '  Reviewers: bob'))
    assert.is_true(vim.tbl_contains(lines, '  Labels: bug'))
    assert.is_true(vim.tbl_contains(lines, '  Assignees: alice'))
    assert.is_true(vim.tbl_contains(lines, '  Milestone: v1'))
  end)

  it('hides the local diff stat when the checked-out branch differs from the PR head', function()
    captured.diff_stat =
      ' lua/forge/init.lua | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)\n'

    local compose = require('forge.compose')
    compose.open_pr_edit(
      {
        labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
        capabilities = { draft = true, reviewers = true },
        name = 'github',
      },
      '23',
      {
        title = 'PR title',
        body = 'PR body',
        draft = false,
        head_branch = 'real-pr-head',
        base_branch = 'main',
        reviewers = {},
        labels = {},
        assignees = {},
        milestone = '',
      },
      'other-local-branch'
    )

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      assert.is_false(line == '  Changes not in origin/main:')
      assert.is_false(line == '   lua/forge/init.lua | 2 +-')
    end
    assert.is_true(vim.tbl_contains(lines, '  Draft: false'))
    assert.is_false(vim.tbl_contains(lines, '  Reviewers: '))
    assert.is_false(vim.tbl_contains(lines, '  Labels: '))
    assert.is_false(vim.tbl_contains(lines, '  Assignees: '))
    assert.is_false(vim.tbl_contains(lines, '  Milestone: '))
  end)

  it('extracts PR metadata from the comment block on write', function()
    local compose = require('forge.compose')
    local f = {
      labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
      capabilities = { draft = true, reviewers = true },
      name = 'github',
      update_pr_cmd = function(_, num, title, body, ref, metadata)
        captured.args = {
          num = num,
          title = title,
          body = body,
          ref = ref,
          metadata = metadata,
        }
        return { 'update-pr', num, title, body }
      end,
    }

    compose.open_pr_edit(f, '23', {
      title = 'PR title',
      body = 'PR body',
      draft = false,
      head_branch = 'real-pr-head',
      base_branch = 'main',
      reviewers = { 'bob' },
      labels = { 'bug' },
      assignees = { 'alice' },
      milestone = 'v1',
    }, 'real-pr-head')

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '# updated pr',
      '',
      'updated body',
      '',
      '<!--',
      '  Draft: true',
      '  Reviewers: carol, dave',
      '  Labels: bug, docs',
      '  Assignees: alice, bob',
      '  Milestone: v2',
      '-->',
    })
    vim.cmd('write')

    vim.wait(100, function()
      return captured.args ~= nil and captured.cleared == 1
    end)

    assert.same({
      num = '23',
      title = 'updated pr',
      body = 'updated body',
      ref = nil,
      metadata = {
        labels = { 'bug', 'docs' },
        assignees = { 'alice', 'bob' },
        milestone = 'v2',
        draft = true,
        reviewers = { 'carol', 'dave' },
      },
    }, captured.args)
    assert.equals(1, captured.cleared)
    assert.same({}, captured.warns)
    assert.same({}, captured.errors)
  end)

  it('uses submission semantics to hide unsupported draft edits while keeping reviewers', function()
    local compose = require('forge.compose')
    compose.open_pr_edit(
      {
        labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
        capabilities = { draft = false, reviewers = false },
        submission = {
          pr = {
            update = {
              draft = false,
              reviewers = true,
              labels = true,
              assignees = false,
              milestone = true,
            },
          },
        },
        name = 'codeberg',
      },
      '23',
      {
        title = 'PR title',
        body = 'PR body',
        draft = true,
        head_branch = 'real-pr-head',
        base_branch = 'main',
        reviewers = { 'bob' },
        labels = { 'bug' },
        assignees = { 'alice' },
        milestone = 'v1',
      },
      'real-pr-head'
    )

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.is_false(vim.tbl_contains(lines, '  Draft: true'))
    assert.is_true(vim.tbl_contains(lines, '  Reviewers: bob'))
    assert.is_true(vim.tbl_contains(lines, '  Labels: bug'))
    assert.is_false(vim.tbl_contains(lines, '  Assignees: alice'))
    assert.is_true(vim.tbl_contains(lines, '  Milestone: v1'))
  end)
end)
