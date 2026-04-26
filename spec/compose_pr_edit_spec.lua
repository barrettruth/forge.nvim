vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('compose pr edit', function()
  local captured
  local old_fn_system
  local old_system
  local old_feedkeys
  local old_preload

  local function line_index(lines, target)
    for i, line in ipairs(lines) do
      if line == target then
        return i
      end
    end
    return nil
  end

  local function extmark_groups_for_line(buf, target)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line_num = line_index(lines, target)
    assert.is_not_nil(line_num)
    local ns = vim.api.nvim_get_namespaces().forge_compose
    local extmarks = vim.api.nvim_buf_get_extmarks(
      buf,
      ns,
      { line_num - 1, 0 },
      { line_num - 1, -1 },
      { details = true }
    )
    local groups = {}
    for _, extmark in ipairs(extmarks) do
      table.insert(groups, extmark[4].hl_group)
    end
    table.sort(groups)
    return groups
  end

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
        and vim.api.nvim_buf_get_name(buf) == 'forge://github.com/owner/repo/pr/23/edit'
      then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.cmd('enew!')
  end)

  it('leaves PR edit buffers at the default cursor and mode state', function()
    local compose = require('forge.compose')
    local old_set_cursor = vim.api.nvim_win_set_cursor
    local old_feedkeys_local = vim.api.nvim_feedkeys
    local old_cmd = vim.cmd
    local cursor_calls = {}
    local feedkeys_calls = {}
    local cmd_calls = {}

    vim.api.nvim_win_set_cursor = function(win, pos)
      cursor_calls[#cursor_calls + 1] = { win = win, pos = { pos[1], pos[2] } }
      return old_set_cursor(win, pos)
    end
    vim.api.nvim_feedkeys = function(keys, mode, escape_ks)
      feedkeys_calls[#feedkeys_calls + 1] = { keys = keys, mode = mode, escape_ks = escape_ks }
    end
    vim.cmd = function(cmd)
      cmd_calls[#cmd_calls + 1] = cmd
      return old_cmd(cmd)
    end

    local ok, err = pcall(function()
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
        'real-pr-head'
      )
    end)

    vim.api.nvim_win_set_cursor = old_set_cursor
    vim.api.nvim_feedkeys = old_feedkeys_local
    vim.cmd = old_cmd

    if not ok then
      error(err)
    end

    assert.same({}, cursor_calls)
    assert.same({}, feedkeys_calls)
    assert.is_false(vim.tbl_contains(cmd_calls, 'normal! v$h'))
    assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
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
    local editing_line = line_index(lines, '  Editing Pull Request #23 via github.')

    assert.is_not_nil(editing_line)
    assert.equals('  On branch real-pr-head against main.', lines[editing_line + 1])
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

  it(
    'keeps a single blank line after the branch line when metadata and diff stat are empty',
    function()
      local compose = require('forge.compose')
      compose.open_pr_edit(
        {
          labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
          capabilities = { draft = false, reviewers = false },
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
      local editing_line = line_index(lines, '  Editing Pull Request #23 via github.')

      assert.is_not_nil(editing_line)
      assert.equals('  On branch real-pr-head against main.', lines[editing_line + 1])
      assert.equals('', lines[editing_line + 2])
      assert.equals('  Writing (:w) submits this buffer.', lines[editing_line + 3])
    end
  )

  it('keeps PR edit accents narrow and splits mixed diff-stat runs', function()
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
        head_branch = 'feature',
        base_branch = 'main',
        reviewers = {},
        labels = {},
        assignees = {},
        milestone = '',
      },
      'feature'
    )

    assert.same(
      { 'ForgeComposeForge' },
      extmark_groups_for_line(0, '  Editing Pull Request #23 via github.')
    )
    assert.same(
      { 'ForgeComposeBranch' },
      extmark_groups_for_line(0, '  Changes not in origin/main:')
    )
    assert.same(
      { 'ForgeComposeAdded', 'ForgeComposeFile', 'ForgeComposeRemoved' },
      extmark_groups_for_line(0, '   lua/forge/init.lua | 2 +-')
    )
    assert.same({}, extmark_groups_for_line(0, '   1 file changed, 1 insertion(+), 1 deletion(-)'))
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
