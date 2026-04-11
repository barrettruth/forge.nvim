vim.opt.runtimepath:prepend(vim.fn.getcwd())

describe(':Forge command', function()
  local captured
  local old_preload
  local old_systemlist

  before_each(function()
    captured = {
      opens = {},
      pr_action_num = nil,
      reviews = {},
      review_actions = {},
      warnings = {},
      closed_prs = {},
      closed_issues = {},
    }
    old_preload = {
      ['forge'] = package.preload['forge'],
      ['forge.logger'] = package.preload['forge.logger'],
      ['forge.pickers'] = package.preload['forge.pickers'],
      ['forge.review'] = package.preload['forge.review'],
    }
    old_systemlist = vim.fn.systemlist

    package.preload['forge.logger'] = function()
      return {
        warn = function(msg)
          table.insert(captured.warnings, msg)
        end,
        info = function() end,
        debug = function() end,
        error = function() end,
      }
    end

    package.preload['forge'] = function()
      return {
        detect = function()
          return {
            capabilities = {
              per_pr_checks = true,
            },
            labels = {
              pr_one = 'PR',
            },
            kinds = {
              pr = 'pr',
              issue = 'issue',
            },
          }
        end,
        current_context = function()
          return {
            root = '/repo',
            branch = 'main',
            head = 'abc123',
          }
        end,
        create_pr = function(opts)
          captured.create_pr = opts
        end,
        edit_pr = function(num)
          captured.edit_pr = num
        end,
        create_issue = function(opts)
          captured.create_issue = opts
        end,
        clear_cache = function()
          captured.cleared = true
        end,
        open = function(route, opts)
          table.insert(captured.opens, { route = route, opts = opts })
        end,
        template_slugs = function()
          return {}
        end,
      }
    end

    package.preload['forge.pickers'] = function()
      return {
        pr_actions = function(_, num)
          captured.pr_action_num = num
          return {
            review = function()
              table.insert(captured.reviews, num)
            end,
            checkout = function() end,
            worktree = function() end,
          }
        end,
        checks = function() end,
        ci = function() end,
        pr_manage = function() end,
        pr_close = function(_, num)
          table.insert(captured.closed_prs, num)
        end,
        pr_reopen = function() end,
        issue_close = function(_, num)
          table.insert(captured.closed_issues, num)
        end,
        issue_reopen = function() end,
      }
    end

    package.preload['forge.review'] = function()
      return {
        toggle = function()
          table.insert(captured.review_actions, 'toggle')
        end,
        stop = function()
          table.insert(captured.review_actions, 'end')
        end,
        files = function()
          table.insert(captured.review_actions, 'files')
        end,
        next_file = function()
          table.insert(captured.review_actions, 'next-file')
        end,
        prev_file = function()
          table.insert(captured.review_actions, 'prev-file')
        end,
        next_hunk = function()
          table.insert(captured.review_actions, 'next-hunk')
        end,
        prev_hunk = function()
          table.insert(captured.review_actions, 'prev-hunk')
        end,
        start_branch = function(_, branch)
          table.insert(captured.review_actions, 'branch:' .. branch)
        end,
        start_commit = function(_, sha)
          table.insert(captured.review_actions, 'commit:' .. sha)
        end,
      }
    end

    vim.fn.systemlist = function(cmd)
      if cmd == 'git for-each-ref --format=%(refname:short) refs/heads refs/tags' then
        return { 'main', 'feature' }
      end
      return old_systemlist(cmd)
    end

    if vim.api.nvim_get_commands({ builtin = false }).Forge then
      vim.api.nvim_del_user_command('Forge')
    end

    package.loaded['forge'] = nil
    package.loaded['forge.cmd'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.pickers'] = nil
    package.loaded['forge.review'] = nil

    dofile(vim.fn.getcwd() .. '/plugin/forge.lua')
  end)

  after_each(function()
    vim.fn.systemlist = old_systemlist
    package.preload['forge'] = old_preload['forge']
    package.preload['forge.logger'] = old_preload['forge.logger']
    package.preload['forge.pickers'] = old_preload['forge.pickers']
    package.preload['forge.review'] = old_preload['forge.review']
    package.loaded['forge'] = nil
    package.loaded['forge.cmd'] = nil
    package.loaded['forge.logger'] = nil
    package.loaded['forge.pickers'] = nil
    package.loaded['forge.review'] = nil
    if vim.api.nvim_get_commands({ builtin = false }).Forge then
      vim.api.nvim_del_user_command('Forge')
    end
  end)

  it('dispatches :Forge pr review to the PR review action', function()
    vim.cmd('Forge pr review 42')

    assert.equals('42', captured.pr_action_num)
    assert.same({ '42' }, captured.reviews)
  end)

  it('keeps :Forge pr diff as an alias for the PR review action', function()
    vim.cmd('Forge pr diff 7')

    assert.equals('7', captured.pr_action_num)
    assert.same({ '7' }, captured.reviews)
  end)

  it('dispatches review navigation subcommands', function()
    vim.cmd('Forge review files')
    vim.cmd('Forge review next-file')
    vim.cmd('Forge review prev-file')
    vim.cmd('Forge review next-hunk')
    vim.cmd('Forge review prev-hunk')

    assert.same(
      { 'files', 'next-file', 'prev-file', 'next-hunk', 'prev-hunk' },
      captured.review_actions
    )
  end)

  it('dispatches branch and commit review launchers', function()
    vim.cmd('Forge review branch feature')
    vim.cmd('Forge review commit deadbeef')

    assert.same({ 'branch:feature', 'commit:deadbeef' }, captured.review_actions)
  end)

  it('dispatches git-local route subcommands', function()
    vim.cmd('Forge branches')
    vim.cmd('Forge commits feature')
    vim.cmd('Forge worktrees')

    assert.equals('branches', captured.opens[1].route)
    assert.is_nil(captured.opens[1].opts)
    assert.equals('commits', captured.opens[2].route)
    assert.same({ branch = 'feature' }, captured.opens[2].opts)
    assert.equals('worktrees', captured.opens[3].route)
    assert.is_nil(captured.opens[3].opts)
  end)

  it('dispatches browse subcommands through the route aliases', function()
    vim.cmd('Forge browse')
    vim.cmd('Forge browse --root')
    vim.cmd('Forge browse --commit')

    assert.equals('browse.contextual', captured.opens[1].route)
    assert.equals('browse.branch', captured.opens[2].route)
    assert.equals('browse.commit', captured.opens[3].route)
  end)

  it('dispatches normalized create and clear commands through the command layer', function()
    vim.cmd('Forge pr create --draft --fill --web')
    vim.cmd('Forge issue create --blank --template=bug')
    vim.cmd('Forge clear')

    assert.same({ draft = true, instant = true, web = true, scope = nil }, captured.create_pr)
    assert.same({ web = false, blank = true, template = 'bug', scope = nil }, captured.create_issue)
    assert.is_true(captured.cleared)
  end)

  it('rejects unsupported bang with E477 and no side effects', function()
    local ok, err = pcall(vim.cmd, 'Forge! pr review 42')

    assert.is_false(ok)
    assert.matches('E477: No ! allowed', err)
    assert.is_nil(captured.pr_action_num)
  end)

  it('allows supported bang on close subcommands', function()
    vim.cmd('Forge! pr close 42')
    vim.cmd('Forge! issue close 9')

    assert.same({ '42' }, captured.closed_prs)
    assert.same({ '9' }, captured.closed_issues)
  end)

  it('completes git-local subcommands and commit refs', function()
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge br', 'cmdline'), 'branches'))
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge comm', 'cmdline'), 'commits'))
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge work', 'cmdline'), 'worktrees'))
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge commits ', 'cmdline'), 'main'))
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Forge commits f', 'cmdline'), 'feature'))
  end)
end)
