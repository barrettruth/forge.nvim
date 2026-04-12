vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe('compose pr edit', function()
  local old_fn_system
  local old_feedkeys

  before_each(function()
    old_fn_system = vim.fn.system
    old_feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function() end
  end)

  after_each(function()
    vim.fn.system = old_fn_system
    vim.api.nvim_feedkeys = old_feedkeys

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

  it('shows fetched head/base metadata in the header', function()
    vim.fn.system = function(cmd)
      if cmd == 'git diff --stat origin/main..HEAD' then
        return ''
      end
      return ''
    end

    local compose = require('forge.compose')
    compose.open_pr_edit(
      {
        labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
        name = 'github',
      },
      '23',
      {
        title = 'PR title',
        body = 'PR body',
        head_branch = 'real-pr-head',
        base_branch = 'main',
      },
      'other-local-branch'
    )

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.is_truthy(vim.tbl_contains(lines, '  On branch real-pr-head against main.'))
    assert.is_false(vim.tbl_contains(lines, '  On branch other-local-branch against main.'))
    assert.is_false(vim.tbl_contains(lines, '  Draft: false'))
    assert.is_false(vim.tbl_contains(lines, '  Reviewers: bob'))
    assert.is_false(vim.tbl_contains(lines, '  Labels: bug'))
    assert.is_false(vim.tbl_contains(lines, '  Assignees: alice'))
    assert.is_false(vim.tbl_contains(lines, '  Milestone: v1'))
  end)

  it('hides the local diff stat when the checked-out branch differs from the PR head', function()
    vim.fn.system = function(cmd)
      if cmd == 'git diff --stat origin/main..HEAD' then
        return ' lua/forge/init.lua | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)\n'
      end
      return ''
    end

    local compose = require('forge.compose')
    compose.open_pr_edit(
      {
        labels = { pr_full = 'Pull Requests', pr_one = 'PR' },
        name = 'github',
      },
      '23',
      {
        title = 'PR title',
        body = 'PR body',
        head_branch = 'real-pr-head',
        base_branch = 'main',
      },
      'other-local-branch'
    )

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      assert.is_false(line == '  Changes not in origin/main:')
      assert.is_false(line == '   lua/forge/init.lua | 2 +-')
    end
  end)
end)
